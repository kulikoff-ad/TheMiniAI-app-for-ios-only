import SwiftUI

struct HomeView: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @EnvironmentObject var library: ModelLibrary
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var agents: AgentStore
    @EnvironmentObject var runtime: AgentRuntime
    @AppStorage("offlineMode") private var offlineMode = false
    @State private var showFinder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if offlineMode { offlineBanner }
                    quickActions
                    if !downloads.active.isEmpty { activeDownloads }
                    storageCard
                    recentModels
                    agentsStrip
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("AI Agent Hub")
            .sheet(isPresented: $showFinder) { ModelFinderView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Download AI from Hugging Face.\nBuild agents. Create anything.")
                .font(.system(size: 21, weight: .bold, design: .rounded))
            HStack(spacing: 8) {
                Pill(text: hf.user.map { "🤗 \($0.name)" } ?? "🤗 Not connected",
                     color: hf.user == nil ? Theme.textDim : Theme.accent)
                Pill(text: "\(library.models.count) models", color: Theme.accent2, icon: "cube.box")
                Pill(text: "\(agents.agents.count) agents", color: Theme.good, icon: "cpu")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline Mode is on").font(.subheadline.weight(.semibold))
                Text("Inference runs on-device, files stay local, and no history leaves the phone.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.warn.opacity(0.5)))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick actions")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink { HuggingFaceBrowserView() } label: {
                    QuickTile(emoji: "🤗", title: "Hugging Face", subtitle: "Search & download models", tint: Theme.accent)
                }
                Button { showFinder = true } label: {
                    QuickTile(emoji: "🧭", title: "Find Model for Task", subtitle: "Describe what you need", tint: Theme.accent2)
                }
                NavigationLink { AgentEditorView(agent: nil) } label: {
                    QuickTile(emoji: "🤖", title: "Create Agent", subtitle: "Tools & permissions", tint: Theme.good)
                }
                NavigationLink { WorkspaceView(embedded: true) } label: {
                    QuickTile(emoji: "🛠", title: "Workspace", subtitle: "Run a task now", tint: Theme.warn)
                }
            }
        }
    }

    private var activeDownloads: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Downloads", subtitle: "\(downloads.active.count) in progress")
            ForEach(downloads.active) { info in
                DownloadRow(info: info)
            }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Device")
            HStack {
                statColumn("Free space", Fmt.bytes(library.freeDiskBytes))
                Divider().overlay(Theme.stroke)
                statColumn("Models on disk", Fmt.bytes(library.usedBytes))
                Divider().overlay(Theme.stroke)
                statColumn("RAM budget", Fmt.bytes(DeviceCapabilities.usableMemoryBudgetBytes))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func statColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Theme.textDim)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var recentModels: some View {
        if library.models.isEmpty {
            EmptyStateView(icon: "cube.transparent",
                           title: "No models yet",
                           message: "Browse Hugging Face and download a GGUF or Core ML file to get started.")
                .card()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "My models")
                ForEach(library.sorted.prefix(3)) { model in
                    NavigationLink { LocalModelDetailView(model: model) } label: {
                        LocalModelRow(model: model)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var agentsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Agents")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(agents.agents) { agent in
                        NavigationLink { WorkspaceView(preselected: agent, embedded: true) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(agent.name).font(.subheadline.weight(.semibold))
                                Text(agent.descriptionText).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(2)
                                HStack(spacing: 4) {
                                    ForEach(Array(agent.tools).sorted(by: { $0.rawValue < $1.rawValue })) { t in
                                        Text(t.emoji).font(.caption2)
                                    }
                                }
                            }
                            .frame(width: 170, alignment: .leading)
                            .card(padding: 12)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct QuickTile: View {
    let emoji: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.title2)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(subtitle).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.35)))
    }
}

struct DownloadRow: View {
    let info: DownloadTaskInfo
    @EnvironmentObject var downloads: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((info.fileName as NSString).lastPathComponent)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(info.repoId).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                Spacer()
                Pill(text: info.state.title, color: color(for: info.state))
            }
            ProgressView(value: info.progress).tint(Theme.accent)
            HStack {
                Text("\(Fmt.bytes(info.receivedBytes)) / \(Fmt.bytes(info.totalBytes))")
                    .font(.caption2).foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int(info.progress * 100))%").font(.caption2).foregroundStyle(Theme.textDim)
            }
            if let err = info.errorMessage {
                Text(err).font(.caption2).foregroundStyle(Theme.bad)
            }
            HStack(spacing: 8) {
                if info.state == .downloading {
                    Button { downloads.pause(info.id) } label: { Label("Pause", systemImage: "pause.fill") }
                } else if info.state == .paused || info.state == .failed {
                    Button { downloads.resume(info.id) } label: { Label("Resume", systemImage: "play.fill") }
                }
                Button(role: .destructive) { downloads.cancel(info.id) } label: { Label("Cancel", systemImage: "xmark") }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .card()
    }

    private func color(for state: DownloadState) -> Color {
        switch state {
        case .downloading: return Theme.accent2
        case .completed: return Theme.good
        case .failed: return Theme.bad
        case .paused: return Theme.warn
        default: return Theme.textDim
        }
    }
}
