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
            Agent(name: "Coding Agent",
                  descriptionText: "Создаёт и редактирует код, создаёт проекты, делает коммиты через GitHub.",
                  systemPrompt: "You are a senior software engineer. Always inspect existing code before editing. Keep diffs minimal, write tests, and explain your changes. Plan with tools: list files, then write.",
                  temperature: 0.25, maxTokens: 3072,
                  tools: [.files, .github, .web],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: true,
                                                allowGitHubWrite: true, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: false)),
            Agent(name: "File Agent",
                  descriptionText: "Создаёт и изменяет файлы, папки, ZIP, анализирует документы и генерирует проекты в Workspace.",
                  systemPrompt: "You are a file assistant. Create, read and edit files in Documents/Workspace. Use zip to archive and tree to inspect. Always confirm before deleting.",
                  temperature: 0.4, maxTokens: 2048,
                  tools: [.files],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: false,
                                                allowGitHubWrite: false, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: false)),
            Agent(name: "Web Research Agent",
                  descriptionText: "Ищет информацию в интернете, открывает страницы, собирает отчёт.",
                  systemPrompt: "You are a meticulous researcher. Search the web, fetch pages, follow links, collect facts and write a sourced markdown report into Workspace/report.md. Cite URLs.",
                  temperature: 0.5, maxTokens: 2048,
                  tools: [.web, .files],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: true,
                                                allowGitHubWrite: false, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: false)),
            Agent(name: "GitHub Agent",
                  descriptionText: "Работает с GitHub repositories: создаёт файлы, ветки, коммиты, PRs, показывает diff.",
                  systemPrompt: "You are a GitHub assistant. Work with repositories: list, read code, create branches, commit files and open PRs. Always show the diff and ask for confirmation before pushing.",
                  temperature: 0.3, maxTokens: 3072,
                  tools: [.github, .files],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: true,
                                                allowGitHubWrite: true, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: false)),
            Agent(name: "Phone AI Agent",
                  descriptionText: "Оптимизирован для запуска локальных GGUF/Core ML моделей на iPhone.",
                  systemPrompt: "You are optimized for on-device inference. Prefer small GGUF/Core ML models, keep context short, and never call cloud tools. Be concise.",
                  temperature: 0.7, maxTokens: 1536,
                  tools: [.files],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: false,
                                                allowGitHubWrite: false, allowComputerControl: false,
                                                requireConfirmationBeforePush: true, offlineOnly: true)),
            Agent(name: "PC Agent",
                  descriptionText: "Работает с компьютером через Companion-клиент: файлы, команды, тесты, отправка результатов на iPhone.",
                  systemPrompt: "You work with the user's computer via the Companion app. List, read and write files there, run approved commands, execute tests and send results back to the phone. Ask for confirmation before dangerous actions.",
                  temperature: 0.4, maxTokens: 3072,
                  tools: [.computer, .files],
                  permissions: AgentPermissions(allowFileWrite: true, allowFileDelete: false, allowNetwork: true,
                                                allowGitHubWrite: false, allowComputerControl: true,
                                                requireConfirmationBeforePush: true, offlineOnly: false))
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
