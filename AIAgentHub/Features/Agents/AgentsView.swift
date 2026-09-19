import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink { AgentEditorView(agent: nil) } label: {
                        Label("Create Agent", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent2)

                    ForEach(store.agents) { agent in
                        NavigationLink { AgentEditorView(agent: agent) } label: { AgentRow(agent: agent) }
                            .buttonStyle(.plain)
                    }

                    if !store.history.isEmpty {
                        SectionHeader(title: "Recent runs")
                        ForEach(store.history.prefix(8)) { run in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.task).font(.caption).lineLimit(2)
                                HStack {
                                    Pill(text: run.status.title, color: run.status == .finished ? Theme.good : Theme.textDim)
                                    Text(Fmt.ago(run.startedAt)).font(.caption2).foregroundStyle(Theme.textDim)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 12)
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Agents")
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(agent.name).font(.subheadline.weight(.semibold))
                Spacer()
                if agent.permissions.offlineOnly { Pill(text: "Offline", color: Theme.warn, icon: "wifi.slash") }
            }
            if !agent.descriptionText.isEmpty {
                Text(agent.descriptionText).font(.caption).foregroundStyle(Theme.textDim).lineLimit(2)
            }
            HStack(spacing: 6) {
                Pill(text: agent.binding.isLocal ? "Local model" : agent.binding.displayName, color: Theme.accent2)
                ForEach(Array(agent.tools).sorted(by: { $0.rawValue < $1.rawValue })) { t in
                    Pill(text: "\(t.emoji) \(t.title)", color: Theme.good)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct AgentEditorView: View {
    @EnvironmentObject var store: AgentStore
    @EnvironmentObject var library: ModelLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var agent: Agent
    @State private var useLocal: Bool
    @State private var localId: UUID?
    @State private var cloudProvider: CloudProvider
    @State private var cloudModel: String
    private let isNew: Bool

    init(agent: Agent?) {
        let a = agent ?? Agent(name: "New Agent")
        _agent = State(initialValue: a)
        isNew = agent == nil
        switch a.binding {
        case .local(let id):
            _useLocal = State(initialValue: true); _localId = State(initialValue: id)
            _cloudProvider = State(initialValue: .huggingFace)
            _cloudModel = State(initialValue: "Qwen/Qwen2.5-7B-Instruct")
        case .cloud(let p, let m):
            _useLocal = State(initialValue: false); _localId = State(initialValue: nil)
            _cloudProvider = State(initialValue: p); _cloudModel = State(initialValue: m)
        }
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $agent.name)
                TextField("Description", text: $agent.descriptionText, axis: .vertical).lineLimit(2...4)
            }

            Section("Model") {
                Picker("Source", selection: $useLocal) {
                    Text("Cloud Model").tag(false)
                    Text("Downloaded HF Model").tag(true)
                }.pickerStyle(.segmented)

                if useLocal {
                    if library.models.isEmpty {
                        Text("No downloaded models. Get one from the 🤗 Hugging Face tab.")
                            .font(.caption).foregroundStyle(Theme.textDim)
                    } else {
                        Picker("Local model", selection: $localId) {
                            Text("Select…").tag(UUID?.none)
                            ForEach(library.models) { m in
                                Text("\(m.displayName) · \(m.format.title)").tag(UUID?.some(m.id))
                            }
                        }
                        if let id = localId, let m = library.model(withId: id) {
                            let c = DeviceCapabilities.evaluate(model: m)
                            if !c.canRun {
                                Label(c.reason ?? "Incompatible", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(Theme.bad)
                            }
                        }
                    }
                } else {
                    Picker("Provider", selection: $cloudProvider) {
                        ForEach(CloudProvider.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Model id", text: $cloudModel)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }

            Section("Behaviour") {
                VStack(alignment: .leading) {
                    Text("System Prompt").font(.caption).foregroundStyle(Theme.textDim)
                    TextEditor(text: $agent.systemPrompt).frame(height: 110).font(.system(size: 13, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    HStack { Text("Temperature"); Spacer(); Text(String(format: "%.2f", agent.temperature)).foregroundStyle(Theme.textDim) }
                    Slider(value: $agent.temperature, in: 0...1.5, step: 0.05)
                }
                Stepper("Max Tokens: \(agent.maxTokens)", value: $agent.maxTokens, in: 256...8192, step: 256)
            }

            Section("Tools") {
                ForEach(AgentToolKind.allCases.filter { $0 != .shellSandbox }) { tool in
                    Toggle(isOn: Binding(
                        get: { agent.tools.contains(tool) },
                        set: { on in if on { agent.tools.insert(tool) } else { agent.tools.remove(tool) } })) {
                            Label("\(tool.emoji) \(tool.title)", systemImage: tool.symbol)
                        }
                }
            }

            Section("Permissions") {
                Toggle("Create & edit files", isOn: $agent.permissions.allowFileWrite)
                Toggle("Delete files", isOn: $agent.permissions.allowFileDelete)
                Toggle("Network access", isOn: $agent.permissions.allowNetwork)
                Toggle("GitHub write (branch, commit, PR)", isOn: $agent.permissions.allowGitHubWrite)
                Toggle("Control paired computer", isOn: $agent.permissions.allowComputerControl)
                Toggle("Always confirm before publishing", isOn: $agent.permissions.requireConfirmationBeforePush)
                Toggle("Offline Mode (device only)", isOn: $agent.permissions.offlineOnly)
                if agent.permissions.offlineOnly {
                    Text("Offline Mode requires a downloaded model and disables web + GitHub tools.")
                        .font(.caption2).foregroundStyle(Theme.warn)
                }
            }

            if !isNew {
                Section {
                    Button("Delete agent", role: .destructive) { store.delete(agent); dismiss() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(isNew ? "Create Agent" : agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(agent.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        if useLocal, let id = localId {
            agent.binding = .local(modelId: id)
        } else {
            agent.binding = .cloud(provider: cloudProvider, model: cloudModel)
        }
        if agent.permissions.offlineOnly {
            agent.permissions.allowNetwork = false
            agent.tools.remove(.web); agent.tools.remove(.github); agent.tools.remove(.computer)
        }
        store.upsert(agent)
        dismiss()
    }
}
