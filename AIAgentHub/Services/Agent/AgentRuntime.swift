import Foundation
import Combine

/// Executes an agent: builds a plan with the bound model, then runs a ReAct-style
/// tool loop. Every action is emitted as an event so the Workspace can show it live.
@MainActor
final class AgentRuntime: ObservableObject {

    static let shared = AgentRuntime()

    @Published private(set) var run: AgentRun?
    @Published private(set) var isBusy = false
    @Published var pendingConfirmation: PendingAction?

    struct PendingAction: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let diff: String?
        let perform: () async -> String
    }

    private var task: Task<Void, Never>?
    private var engine: InferenceEngine?
    private var transcript: [ChatMessage] = []

    // MARK: - Lifecycle

    func start(agent: Agent, task userTask: String, gitHubContext: GitHubTargetContext? = nil) {
        cancel()
        var newRun = AgentRun(agentId: agent.id, task: userTask, status: .planning)
        newRun.events.append(.init(kind: .info, title: "Task received", body: userTask))
        run = newRun
        isBusy = true

        self.task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.execute(agent: agent, userTask: userTask, gitHub: gitHubContext)
                self.finish(status: .finished)
            } catch is CancellationError {
                self.finish(status: .cancelled)
            } catch {
                self.emit(.init(kind: .error, title: "Run failed", body: error.localizedDescription))
                self.finish(status: .failed)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if run?.status == .running || run?.status == .planning { finish(status: .cancelled) }
        isBusy = false
    }

    private func finish(status: AgentRunStatus) {
        run?.status = status
        run?.finishedAt = Date()
        if let r = run { AgentStore.shared.record(r) }
        isBusy = false
        if let engine { Task { await engine.unload() } }
        engine = nil
    }

    private func emit(_ event: AgentEvent) {
        run?.events.append(event)
    }

    private func setPlan(_ titles: [String]) {
        run?.plan = titles.map { PlanStep(title: $0) }
    }

    private func advancePlan(to index: Int) {
        guard var r = run else { return }
        for i in r.plan.indices {
            if i < index { if r.plan[i].state != .failed { r.plan[i].state = .done } }
            else if i == index { r.plan[i].state = .active }
        }
        run = r
    }

    private func completePlan() {
        guard var r = run else { return }
        for i in r.plan.indices where r.plan[i].state != .failed { r.plan[i].state = .done }
        run = r
    }

    // MARK: - Core loop

    private func execute(agent: Agent, userTask: String, gitHub: GitHubTargetContext?) async throws {
        engine = try makeEngine(for: agent)
        emit(.init(kind: .info, title: "Model", body: engine?.displayName ?? "—"))
        try await engine?.load()

        let tools = ToolRegistry(agent: agent, gitHub: gitHub, runtime: self)
        transcript = [
            .init(role: .system, content: systemPrompt(agent: agent, tools: tools)),
            .init(role: .user, content: userTask)
        ]

        // 1. Planning
        run?.status = .planning
        let planText = try await respond(agent: agent, extra: "Reply with a JSON array of 3-6 short plan step titles and nothing else.")
        let steps = Self.parsePlan(planText)
        setPlan(steps.isEmpty ? ["Analyze task", "Execute", "Summarise"] : steps)
        emit(.init(kind: .thought, title: "Plan created", body: run?.plan.map { "• \($0.title)" }.joined(separator: "\n") ?? ""))
        transcript.append(.init(role: .assistant, content: planText))

        // 2. Tool loop
        run?.status = .running
        var stepIndex = 0
        advancePlan(to: 0)

        for iteration in 0..<12 {
            try Task.checkCancellation()
            let reply = try await respond(agent: agent, extra: nil)
            transcript.append(.init(role: .assistant, content: reply))

            if let call = ToolCall.parse(reply) {
                emit(.init(kind: .toolCall, title: "\(call.tool.emoji) \(call.tool.title) · \(call.action)",
                           body: call.prettyArguments, tool: call.tool))
                let result: String
                do {
                    result = try await tools.invoke(call)
                    emit(.init(kind: .toolResult, title: "Result · \(call.action)", body: String(result.prefix(4000)), tool: call.tool))
                } catch {
                    result = "ERROR: \(error.localizedDescription)"
                    emit(.init(kind: .error, title: "Tool failed · \(call.action)", body: error.localizedDescription, tool: call.tool))
                }
                transcript.append(.init(role: .tool, content: "Tool \(call.tool.rawValue).\(call.action) result:\n\(result)"))
                stepIndex = min(stepIndex + 1, max(0, (run?.plan.count ?? 1) - 1))
                advancePlan(to: stepIndex)
                continue
            }

            // No tool call -> final answer
            let final = ToolCall.stripFences(reply)
            run?.output = final
            emit(.init(kind: .output, title: "Final answer", body: final))
            completePlan()
            _ = iteration
            return
        }

        emit(.init(kind: .info, title: "Iteration limit reached",
                   body: "The agent stopped after 12 tool steps to protect battery and tokens."))
        completePlan()
    }

    private func respond(agent: Agent, extra: String?) async throws -> String {
        guard let engine else { throw InferenceError.notLoaded }
        var msgs = transcript
        if let extra { msgs.append(.init(role: .user, content: extra)) }
        return try await engine.complete(messages: msgs,
                                         temperature: agent.temperature,
                                         maxTokens: agent.maxTokens) { _ in }
    }

    private func makeEngine(for agent: Agent) throws -> InferenceEngine {
        switch agent.binding {
        case .cloud(let provider, let model):
            if agent.permissions.offlineOnly {
                throw InferenceError.incompatible("This agent is in Offline Mode but is bound to a cloud model. Bind it to a downloaded model instead.")
            }
            return CloudEngine(provider: provider, modelId: model)
        case .local(let id):
            guard let m = ModelLibrary.shared.model(withId: id) else {
                throw InferenceError.incompatible("The selected local model is no longer installed.")
            }
            ModelLibrary.shared.markUsed(id)
            return try InferenceEngineFactory.make(for: m)
        }
    }

    // MARK: - Confirmation gate

    func requestConfirmation(title: String, detail: String, diff: String?,
                             perform: @escaping () async -> String) async -> String {
        run?.status = .waitingConfirmation
        run?.pendingDiff = diff
        emit(.init(kind: .confirmation, title: "Awaiting your approval", body: title))

        return await withCheckedContinuation { continuation in
            pendingConfirmation = PendingAction(title: title, detail: detail, diff: diff) { [weak self] in
                let out = await perform()
                await MainActor.run {
                    self?.run?.status = .running
                    self?.run?.pendingDiff = nil
                }
                return out
            }
            self.confirmationContinuation = continuation
        }
    }

    private var confirmationContinuation: CheckedContinuation<String, Never>?

    func approvePending() {
        guard let action = pendingConfirmation, let cont = confirmationContinuation else { return }
        pendingConfirmation = nil
        confirmationContinuation = nil
        Task {
            let result = await action.perform()
            emit(.init(kind: .toolResult, title: "Approved · \(action.title)", body: result))
            cont.resume(returning: result)
        }
    }

    func rejectPending() {
        guard pendingConfirmation != nil, let cont = confirmationContinuation else { return }
        pendingConfirmation = nil
        confirmationContinuation = nil
        run?.status = .running
        run?.pendingDiff = nil
        emit(.init(kind: .info, title: "Rejected by user", body: "The change was not published."))
        cont.resume(returning: "User rejected this action. Do not retry it; ask what to change instead.")
    }

    // MARK: - Prompt

    private func systemPrompt(agent: Agent, tools: ToolRegistry) -> String {
        """
        \(agent.systemPrompt)

        You are running inside AI Agent Hub on an iPhone. You work by emitting ONE tool call at a time.

        To call a tool reply with ONLY a JSON object:
        {"tool":"files","action":"write","args":{"path":"src/main.swift","contents":"..."}}

        Available tools and actions:
        \(tools.catalog)

        Rules:
        - One JSON object per reply, no prose around it, when you want to use a tool.
        - When the task is done, reply with the final answer in plain markdown (no JSON).
        - Never invent tool results. Wait for the tool output message.
        - Respect permissions: \(tools.permissionSummary)
        """
    }

    static func parsePlan(_ text: String) -> [String] {
        let cleaned = ToolCall.stripFences(text)
        if let data = cleaned.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr
        }
        // Fallback: bullet lines
        let lines = cleaned.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let bullets = lines.compactMap { line -> String? in
            guard line.hasPrefix("-") || line.hasPrefix("•") || line.first?.isNumber == true else { return nil }
            return line.drop(while: { !$0.isLetter }).trimmingCharacters(in: .whitespaces)
        }
        return Array(bullets.prefix(6))
    }
}

/// Parsed tool invocation emitted by the model.
struct ToolCall {
    let tool: AgentToolKind
    let action: String
    let args: [String: Any]

    var prettyArguments: String {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    func string(_ key: String, default def: String = "") -> String { args[key] as? String ?? def }
    func int(_ key: String, default def: Int) -> Int { args[key] as? Int ?? def }

    static func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "^```[a-zA-Z]*\\n", with: "", options: .regularExpression)
            if let r = t.range(of: "```", options: .backwards) { t = String(t[t.startIndex..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ text: String) -> ToolCall? {
        let cleaned = stripFences(text)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else { return nil }
        let jsonSlice = String(cleaned[start...end])
        guard let data = jsonSlice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolRaw = obj["tool"] as? String,
              let tool = AgentToolKind(rawValue: toolRaw),
              let action = obj["action"] as? String else { return nil }
        return ToolCall(tool: tool, action: action, args: obj["args"] as? [String: Any] ?? [:])
    }
}
