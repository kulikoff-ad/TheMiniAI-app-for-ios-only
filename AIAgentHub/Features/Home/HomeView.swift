import SwiftUI

/// Главный экран — современный AI IDE стиль. 9 разделов как в ТЗ + анимация загрузки и состояния агента.
struct HomeView: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @EnvironmentObject var library: ModelLibrary
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var agents: AgentStore
    @EnvironmentObject var runtime: AgentRuntime
    @AppStorage("offlineMode") private var offlineMode = false
    @State private var showFinder = false
    @State private var animatePulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if offlineMode { offlineBanner }
                    // 9 главных разделов — точно как в ТЗ
                    mainGrid
                    if !downloads.active.isEmpty { activeDownloads }
                    workspacePreview
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.18)).frame(width: 44, height: 44)
                    Text("🤖").font(.title2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Agent Hub").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("Download AI from Hugging Face. Build agents. Create anything.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                Spacer()
                // loading animation
                if runtime.isBusy {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(Theme.accent2).frame(width: 6, height: 6)
                                .scaleEffect(animatePulse ? 1.3 : 0.7)
                                .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i)*0.2), value: animatePulse)
                        }
                    }
                } else {
                    Circle().fill(Theme.good).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.good.opacity(0.5), lineWidth: 6).scaleEffect(animatePulse ? 1.5 : 1).opacity(animatePulse ? 0 : 0.5))
                }
            }
            HStack(spacing: 8) {
                Pill(text: hf.user.map { "🤗 \($0.name)" } ?? "🤗 Not connected", color: hf.user == nil ? Theme.textDim : Theme.accent)
                Pill(text: "\(library.models.count) models", color: Theme.accent2, icon: "cube.box")
                Pill(text: "\(agents.agents.count) agents", color: Theme.good, icon: "cpu")
                if runtime.isBusy { Pill(text: runtime.run?.status.title ?? "Running", color: Theme.accent2, icon: "waveform.path.ecg") }
            }
            // Agent state strip
            if let run = runtime.run, runtime.isBusy {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(Theme.accent2)
                    Text(run.task).font(.caption).lineLimit(1).foregroundStyle(Theme.textDim)
                    Spacer()
                    Text("\(run.events.count) events").font(.caption2).foregroundStyle(Theme.textDim)
                }
                .padding(8)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
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

    // MARK: 9 tiles — ТЗ: Search AI, My Agents, My Models, Hugging Face, Online AI, Files, GitHub, Computer, Settings

    private var mainGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "AI Agent Hub", subtitle: "All tools in one place")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // 1 Search AI — общий поиск
                NavigationLink { HuggingFaceBrowserView() } label: {
                    HomeTile(emoji: "🔎", title: "Search AI", subtitle: "Find models", tint: Theme.accent)
                }
                // 2 My Agents
                NavigationLink { AgentsView() } label: {
                    HomeTile(emoji: "🤖", title: "My Agents", subtitle: "\(agents.agents.count) agents", tint: Theme.good)
                }
                // 3 My Models
                NavigationLink { ModelsView() } label: {
                    HomeTile(emoji: "🧠", title: "My Models", subtitle: "\(library.models.count) local", tint: Theme.accent2)
                }
                // 4 Hugging Face
                NavigationLink { HuggingFaceBrowserView() } label: {
                    HomeTile(emoji: "🤗", title: "Hugging Face", subtitle: "Hub • Download", tint: Theme.accent)
                }
                // 5 Online AI
                NavigationLink { OnlineAIView() } label: {
                    HomeTile(emoji: "🌐", title: "Online AI", subtitle: "Providers • Auto", tint: Theme.accent2)
                }
                // 6 Files
                NavigationLink { FilesView() } label: {
                    HomeTile(emoji: "📁", title: "Files", subtitle: "Workspace", tint: Theme.warn)
                }
                // 7 GitHub
                NavigationLink { GitHubView() } label: {
                    HomeTile(emoji: "🐙", title: "GitHub", subtitle: "Repos • PRs", tint: Theme.textDim)
                }
                // 8 Computer
                NavigationLink { CompanionView() } label: {
                    HomeTile(emoji: "💻", title: "Computer", subtitle: "Companion", tint: Theme.accent2)
                }
                // 9 Settings
                NavigationLink { SettingsView() } label: {
                    HomeTile(emoji: "⚙️", title: "Settings", subtitle: "Keys • Storage", tint: Theme.textDim)
                }
            }
            // extra: Phone AI prominent
            Button { showFinder = true } label: {
                HStack(spacing: 10) {
                    Text("📱").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI for iPhone").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("Find a model that fits this device — size + format + runtime checked").font(.caption2).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textDim)
                }
                .padding(12)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.4)))
            }.buttonStyle(.plain)
            NavigationLink { PhoneAIView() } label: {
                HStack(spacing: 10) {
                    Text("🧭").font(.title3)
                    Text("Full Phone AI filters").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent)
                }.frame(maxWidth: .infinity).padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
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

    private var workspacePreview: some View {
        NavigationLink { WorkspaceView(embedded: true) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("AI Agent Workspace").font(.caption.weight(.bold)).foregroundStyle(Theme.textDim)
                    Spacer()
                    if runtime.isBusy { Pill(text: "Running", color: Theme.accent2) } else { Pill(text: "Idle", color: Theme.textDim) }
                }
                Text(runtime.run?.task ?? "No task yet — tap to create an iOS application with an agent.")
                    .font(.caption).foregroundStyle(Theme.textDim).lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(["📁","🌐","🐙","💻"], id: \.self) { e in Text(e).font(.caption2).opacity(0.7) }
                    Spacer()
                    Text("→ Workspace").font(.caption2).foregroundStyle(Theme.accent2)
                }
            }.card()
        }.buttonStyle(.plain)
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

struct HomeTile: View {
    let emoji: String
    let title: String
    let subtitle: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.title3)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.textDim).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(10)
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
            // Progress bar with % and bytes — ТЗ: ████████████░░░░ 78%  3.1 GB / 4.0 GB
            ProgressView(value: info.progress).tint(Theme.accent)
            HStack {
                Text("\(Fmt.bytes(info.receivedBytes)) / \(Fmt.bytes(info.totalBytes))")
                    .font(.caption2).foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int(info.progress * 100))%").font(.caption2).foregroundStyle(Theme.textDim)
            }
            // Visual bar text for ТЗ compliance
            Text(progressBar(progress: info.progress))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.accent)
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

    private func progressBar(progress: Double) -> String {
        let total = 20
        let filled = Int(progress * Double(total))
        let empty = total - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + " \(Int(progress*100))%"
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
