import Foundation
import Combine

@MainActor
final class AgentStore: ObservableObject {

    static let shared = AgentStore()

    @Published private(set) var agents: [Agent] = []
    @Published private(set) var history: [AgentRun] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("agents.json")
    }()
    private let historyURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("runs.json")
    }()

    init() {
        load()
        if agents.isEmpty { agents = Self.starterAgents; save() }
    }

    private func load() {
        if let d = try? Data(contentsOf: url), let a = try? JSONDecoder().decode([Agent].self, from: d) { agents = a }
        if let d = try? Data(contentsOf: historyURL), let h = try? JSONDecoder().decode([AgentRun].self, from: d) { history = h }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(agents) { try? d.write(to: url, options: .atomic) }
    }

    private func saveHistory() {
        if let d = try? JSONEncoder().encode(history.suffix(50).map { $0 }) {
            try? d.write(to: historyURL, options: .atomic)
        }
    }

    func upsert(_ agent: Agent) {
        if let i = agents.firstIndex(where: { $0.id == agent.id }) { agents[i] = agent } else { agents.append(agent) }
        save()
    }

    func delete(_ agent: Agent) {
        agents.removeAll { $0.id == agent.id }
        save()
    }

    func record(_ run: AgentRun) {
        if let i = history.firstIndex(where: { $0.id == run.id }) { history[i] = run } else { history.insert(run, at: 0) }
        saveHistory()
    }

    func agent(id: UUID) -> Agent? { agents.first { $0.id == id } }

    static var starterAgents: [Agent] {
        [
            Agent(name: "Code Agent",
                  descriptionText: "Plans, writes and reviews code, then commits through GitHub with your approval.",
                  systemPrompt: "You are a senior software engineer. Always inspect existing code before editing. Keep diffs minimal and explain them.",
                  temperature: 0.3, maxTokens: 3072,
                  tools: [.files, .web, .github],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: true,
                                                allowGitHubWrite: true, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: false)),
            Agent(name: "Research Agent",
                  descriptionText: "Searches the web, reads pages and writes a sourced report into your workspace.",
                  systemPrompt: "You are a meticulous researcher. Cite every claim with the URL you read it from.",
                  temperature: 0.5, maxTokens: 2048,
                  tools: [.web, .files]),
            Agent(name: "Offline Writer",
                  descriptionText: "Runs fully on-device with a downloaded model. No network at all.",
                  systemPrompt: "You are a concise writing assistant working entirely offline.",
                  temperature: 0.8, maxTokens: 1536,
                  tools: [.files],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: false,
                                                allowGitHubWrite: false, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: true))
        ]
    }
}

@MainActor
final class GitHubStore: ObservableObject {

    static let shared = GitHubStore()

    @Published var user: GHUser?
    @Published var repos: [GHRepo] = []
    @Published var selected: GHRepo?
    @Published var contents: [GHContent] = []
    @Published var path: String = ""
    @Published var workingBranch: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isConnected: Bool { KeychainStore.has(.githubToken) }

    var context: GitHubTargetContext? {
        guard let r = selected else { return nil }
        let parts = r.fullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return GitHubTargetContext(owner: String(parts[0]), repo: String(parts[1]),
                                   baseBranch: r.defaultBranch, workingBranch: workingBranch)
    }

    func setWorkingBranch(_ name: String) { workingBranch = name }

    func connect() async {
        isLoading = true; errorMessage = nil
        do {
            user = try await GitHubAPI.shared.currentUser()
            repos = try await GitHubAPI.shared.repositories()
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func disconnect() {
        KeychainStore.delete(.githubToken)
        user = nil; repos = []; selected = nil; contents = []; workingBranch = nil
    }

    func open(_ repo: GHRepo) async {
        selected = repo; path = ""; workingBranch = nil
        await loadContents("")
    }

    func loadContents(_ newPath: String) async {
        guard let ctx = context else { return }
        isLoading = true; errorMessage = nil
        do {
            contents = try await GitHubAPI.shared.contents(owner: ctx.owner, repo: ctx.repo,
                                                           path: newPath, ref: workingBranch ?? ctx.baseBranch)
            path = newPath
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func goUp() async {
        guard !path.isEmpty else { return }
        let parent = (path as NSString).deletingLastPathComponent
        await loadContents(parent)
    }
}
