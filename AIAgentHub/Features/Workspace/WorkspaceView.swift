import SwiftUI

struct WorkspaceView: View {
    var preselected: Agent?
    var embedded: Bool = false

    @EnvironmentObject var agents: AgentStore
    @EnvironmentObject var runtime: AgentRuntime
    @EnvironmentObject var github: GitHubStore
    @EnvironmentObject var library: ModelLibrary

    @State private var selectedAgentId: UUID?
    @State private var task: String = ""
    @State private var showFiles = false

    private var agent: Agent? {
        if let id = selectedAgentId { return agents.agent(id: id) }
        return preselected ?? agents.agents.first
    }

    var body: some View {
        content
    }

    @ViewBuilder private var content: some View {
        if embedded { scroll } else { NavigationStack { scroll } }
    }

    private var scroll: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    taskInput
                    if let run = runtime.run {
                        planCard(run)
                        toolsCard
                        outputCard(run)
                        eventsCard(run)
                    } else {
                        EmptyStateView(icon: "sparkles",
                                       title: "Agent Workspace",
                                       message: "Pick an agent, describe the task and watch every step it takes.")
                            .card()
                        toolsCard
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Workspace")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFiles = true } label: { Image(systemName: "folder") }
                }
            }
            .sheet(isPresented: $showFiles) { WorkspaceFilesView() }
            .sheet(item: $runtime.pendingConfirmation) { action in
                ConfirmationSheet(action: action)
            }
            .onAppear { if selectedAgentId == nil { selectedAgentId = preselected?.id ?? agents.agents.first?.id } }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Agent").font(.system(size: 15, weight: .bold, design: .monospaced))
                Spacer()
                Pill(text: runtime.run?.status.title ?? "Idle",
                     color: statusColor(runtime.run?.status ?? .idle))
            }
            Divider().overlay(Theme.stroke)
            Picker("Agent", selection: Binding(get: { selectedAgentId ?? agents.agents.first?.id },
                                               set: { selectedAgentId = $0 })) {
                ForEach(agents.agents) { a in Text(a.name).tag(UUID?.some(a.id)) }
            }
            .pickerStyle(.menu)

            if let agent {
                monoLine("Model:", modelLabel(agent))
                monoLine("Tools:", Array(agent.tools).sorted(by: { $0.rawValue < $1.rawValue }).map { $0.emoji + " " + $0.title }.joined(separator: "  "))
                if let ctx = github.context, agent.tools.contains(.github) {
                    monoLine("Repo:", "\(ctx.fullName) @ \(ctx.workingBranch ?? ctx.baseBranch)")
                }
                if agent.permissions.offlineOnly { monoLine("Mode:", "Offline — inference and files stay on device") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func modelLabel(_ agent: Agent) -> String {
        switch agent.binding {
        case .cloud(let p, let m): return "\(m) (\(p.title))"
        case .local(let id): return library.model(withId: id)?.displayName ?? "missing local model"
        }
    }

    private func monoLine(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(k).font(Theme.mono).foregroundStyle(Theme.textDim)
            Text(v).font(Theme.mono)
        }
    }

    private func statusColor(_ s: AgentRunStatus) -> Color {
        switch s {
        case .running, .planning: return Theme.accent2
        case .finished: return Theme.good
        case .failed: return Theme.bad
        case .waitingConfirmation: return Theme.warn
        default: return Theme.textDim
        }
    }

    // MARK: - Task

    private var taskInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Task")
            TextEditor(text: $task)
                .frame(height: 80)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button {
                    guard let agent else { return }
                    runtime.start(agent: agent, task: task,
                                  gitHubContext: agent.tools.contains(.github) ? github.context : nil)
                } label: {
                    Label("Run", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.good)
                .disabled(task.trimmingCharacters(in: .whitespaces).isEmpty || runtime.isBusy || agent == nil)

                Button(role: .destructive) { runtime.cancel() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(!runtime.isBusy)
            }
        }
        .card()
    }

    // MARK: - Plan / tools / output

    private func planCard(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Plan")
            ForEach(run.plan) { step in
                HStack(alignment: .top, spacing: 8) {
                    Text(step.state.glyph)
                        .font(Theme.mono)
                        .foregroundStyle(step.state == .done ? Theme.good :
                                         step.state == .active ? Theme.accent2 :
                                         step.state == .failed ? Theme.bad : Theme.textDim)
                    Text(step.title).font(Theme.mono)
                        .foregroundStyle(step.state == .pending ? Theme.textDim : .white)
                    Spacer()
                }
            }
            if run.plan.isEmpty { Text("Waiting for the model…").font(.caption).foregroundStyle(Theme.textDim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tools")
            HStack(spacing: 10) {
                ForEach(AgentToolKind.allCases.filter { $0 != .shellSandbox }) { tool in
                    let enabled = agent?.tools.contains(tool) ?? false
                    VStack(spacing: 3) {
                        Text(tool.emoji).font(.title3)
                        Text(tool.title).font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background((enabled ? Theme.good : Theme.textDim).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .opacity(enabled ? 1 : 0.4)
                }
            }
        }
        .card()
    }

    private func outputCard(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Output")
            if run.output.isEmpty {
                Text(run.status == .running || run.status == .planning ? "…working" : "(no output yet)")
                    .font(Theme.mono).foregroundStyle(Theme.textDim)
            } else {
                Text(run.output).font(.callout).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func eventsCard(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Activity", subtitle: "\(run.events.count) events")
            ForEach(run.events.reversed()) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(color(for: e.kind)).frame(width: 6, height: 6)
                        Text(e.title).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Spacer()
                        Text(Fmt.time(e.timestamp)).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                    if !e.body.isEmpty {
                        Text(e.body)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(14)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
    }

    private func color(for kind: AgentEventKind) -> Color {
        switch kind {
        case .error: return Theme.bad
        case .toolCall: return Theme.accent2
        case .toolResult: return Theme.good
        case .output: return Theme.accent
        case .confirmation: return Theme.warn
        default: return Theme.textDim
        }
    }
}

struct ConfirmationSheet: View {
    let action: AgentRuntime.PendingAction
    @EnvironmentObject var runtime: AgentRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(action.title).font(.headline)
                    Text(action.detail).font(.callout).foregroundStyle(Theme.textDim)
                    if let diff = action.diff, !diff.isEmpty {
                        SectionHeader(title: "Changes")
                        DiffView(diff: diff)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Review before publishing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject", role: .destructive) { runtime.rejectPending(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") { runtime.approvePending(); dismiss() }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct DiffView: View {
    let diff: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.hasPrefix("+") ? Theme.good : line.hasPrefix("-") ? Theme.bad : Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WorkspaceFilesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tree: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(tree.isEmpty ? "(empty workspace)" : tree)
                    .font(Theme.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .screenBackground()
            .navigationTitle("Workspace files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { tree = FileTool(permissions: AgentPermissions()).tree() }
        }
    }
}

