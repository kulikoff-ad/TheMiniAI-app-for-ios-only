import SwiftUI

/// ⚙️ Settings — полный набор: AI Providers, Hugging Face, GitHub, Downloads, Storage, Local/Online, Permissions, Computer, Appearance, Language, About
struct SettingsView: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @EnvironmentObject var library: ModelLibrary
    @EnvironmentObject var companion: CompanionClient
    @EnvironmentObject var online: OnlineProviderStore

    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("allowCellularDownloads") private var allowCellular = false
    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("language") private var language: String = "system"

    @State private var hfToken = ""
    @State private var openAIKey = ""
    @State private var showHFConnect = false

    var body: some View {
        NavigationStack {
            Form {
                // AI Providers
                Section("AI Providers") {
                    NavigationLink { OnlineAIView() } label: {
                        HStack {
                            Label("Online AI", systemImage: "cloud")
                            Spacer()
                            Text("\(online.providers.count) providers · \(online.mode.title)").font(.caption).foregroundStyle(Theme.textDim)
                        }
                    }
                    NavigationLink { ModelsView() } label: {
                        HStack {
                            Label("Local Models", systemImage: "cube.box")
                            Spacer()
                            Text("\(library.models.count) installed").font(.caption).foregroundStyle(Theme.textDim)
                        }
                    }
                    HStack {
                        Text("Inference mode")
                        Spacer()
                        Picker("Mode", selection: $online.mode) {
                            ForEach(OnlineMode.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu)
                    }
                }

                Section("🤗 Hugging Face") {
                    if let user = hf.user {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.fullname ?? user.name).font(.subheadline.weight(.semibold))
                                Text("@\(user.name)").font(.caption2).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Button("Disconnect", role: .destructive) { hf.disconnect() }.font(.caption)
                        }
                    } else {
                        Button("Connect Hugging Face") { showHFConnect = true }
                        Text("A User Access Token unlocks gated repos, private models and higher rate limits. Stored in the iOS Keychain — your password is never saved.")
                            .font(.caption2).foregroundStyle(Theme.textDim)
                    }
                }

                Section("🐙 GitHub") {
                    NavigationLink { GitHubView() } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    NavigationLink { ReplaceProjectView() } label: {
                        Label("Replace Existing Project", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                    }
                    Text("Full replacement flow: show old files → confirm delete → upload new AI Agent Hub → show diff → push.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Download Settings") {
                    Toggle("Allow cellular downloads", isOn: $allowCellular)
                    Toggle("Show large download warning (>1 GB)", isOn: .constant(true)).disabled(true)
                    Text("Downloads use a background URLSession (pause / resume / cancel). Check free space before starting a large model.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Storage") {
                    LabeledContent("Free space", value: Fmt.bytes(library.freeDiskBytes))
                    LabeledContent("Used by models", value: Fmt.bytes(library.usedBytes))
                    LabeledContent("Models installed", value: "\(library.models.count)")
                    Button("Open Files → Workspace") {}
                        .disabled(true).font(.caption).foregroundStyle(Theme.textDim)
                }

                Section("Local Models") {
                    NavigationLink { ModelsView() } label: { Label("Manage local models", systemImage: "internaldrive") }
                    Text("GGUF • Core ML • ONNX • MLX. Tap a model to Start/Delete and see compatibility (format + RAM budget + quantization).")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Online Models") {
                    NavigationLink { OnlineAIView() } label: { Label("Provider Manager", systemImage: "server.rack") }
                    ForEach(online.providers.prefix(3)) { p in
                        HStack {
                            Text(p.name).font(.caption)
                            Spacer()
                            Text(p.model).font(.caption2).foregroundStyle(Theme.textDim)
                        }
                    }
                }

                Section("Agent Permissions") {
                    NavigationLink { PermissionsView() } label: {
                        Label("Permission Manager", systemImage: "lock.shield")
                    }
                    Text("Web Access • File Access • GitHub Access • Computer Access • Terminal Access • Network Access • Model Download. Each agent shows its granted permissions as badges.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Computer Connections") {
                    NavigationLink { CompanionView() } label: {
                        HStack {
                            Text("Paired computer")
                            Spacer()
                            Text(companion.isConnected ? (companion.info?.hostname ?? "connected") : "not paired")
                                .foregroundStyle(Theme.textDim).font(.caption)
                        }
                    }
                    Text("Companion clients for macOS / Windows / Linux in the Companion/ folder. Pairing via 6-digit code → PSK in Keychain.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Offline Mode") {
                    Toggle("Offline Mode", isOn: $offlineMode)
                    Text("When on, agents must use a downloaded model, inference runs on device, files stay in the app sandbox and task history is never uploaded.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }.pickerStyle(.segmented)
                    Text("AI Agent Hub uses a dark AI IDE theme by default. This setting is reserved for future light theme support.").font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Language") {
                    Picker("Language", selection: $language) {
                        Text("System").tag("system")
                        Text("English").tag("en")
                        Text("Русский").tag("ru")
                    }.pickerStyle(.segmented)
                    Text("Model search and agent prompts work in both English and Russian. UI language follows the system setting.").font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Device") {
                    LabeledContent("Model", value: DeviceCapabilities.deviceModelIdentifier)
                    LabeledContent("RAM", value: Fmt.bytes(DeviceCapabilities.physicalMemoryBytes))
                    LabeledContent("Model RAM budget", value: Fmt.bytes(DeviceCapabilities.usableMemoryBudgetBytes))
                    LabeledContent("MLX capable", value: DeviceCapabilities.supportsMLX ? "yes" : "no")
                    LabeledContent("Free disk", value: Fmt.bytes(DeviceCapabilities.freeDiskBytes))
                }

                Section("Security") {
                    Button("Erase all stored tokens", role: .destructive) {
                        KeychainStore.wipeAll(); hf.user = nil
                    }
                    Text("Tokens live in the Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly and are never included in backups.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("About") {
                    LabeledContent("AI Agent Hub", value: "1.1.0")
                    Text("Download AI from Hugging Face. Build agents. Create anything.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                    Link("Hugging Face Hub", destination: URL(string: "https://huggingface.co")!)
                    Link("GitHub — Companion & Docs", destination: URL(string: "https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .sheet(isPresented: $showHFConnect) {
                HFConnectSheet()
            }
        }
    }
}

struct PermissionsView: View {
    @EnvironmentObject var agents: AgentStore
    var body: some View {
        List {
            ForEach(agents.agents) { agent in
                Section(agent.name) {
                    ForEach(Permission.allCases) { perm in
                        let granted = PermissionEvaluator.granted(perm, for: agent)
                        HStack {
                            Label(perm.rawValue, systemImage: perm.icon)
                            Spacer()
                            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(granted ? Theme.good : Theme.textDim)
                        }.font(.caption)
                    }
                    Text(agent.descriptionText).font(.caption2).foregroundStyle(Theme.textDim)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Permissions").navigationBarTitleDisplayMode(.inline)
    }
}

struct HFConnectSheet: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("User Access Token") {
                    SecureField("hf_…", text: $token)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Link("Create a token on huggingface.co ↗",
                         destination: URL(string: "https://huggingface.co/settings/tokens")!)
                        .font(.caption)
                }
                Section {
                    Text("AI Agent Hub uses the official Hugging Face User Access Token flow. Create a token with **read** scope (add **write** only if you plan to push). Your password is never entered or stored — only the token, kept in the iOS Keychain.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                if let error { Text(error).font(.caption).foregroundStyle(Theme.bad) }
                Section {
                    Button(busy ? "Verifying…" : "Connect") {
                        Task {
                            busy = true; error = nil
                            let ok = await hf.connect(token: token)
                            busy = false
                            if ok { dismiss() } else { error = "That token was rejected by huggingface.co." }
                        }
                    }
                    .disabled(token.isEmpty || busy)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Connect Hugging Face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct CompanionView: View {
    @EnvironmentObject var companion: CompanionClient
    @State private var host: String = UserDefaults.standard.string(forKey: "companion.host") ?? ""
    @State private var code: String = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section("Host") {
                TextField("http://192.168.1.20:8765", text: $host)
                    .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                SecureField("Pairing code shown by the companion", text: $code)
                Button("Pair") {
                    Task {
                        do { try await companion.pair(pairingCode: code, hostAddress: host); status = "Paired." }
                        catch { status = error.localizedDescription }
                    }
                }.disabled(host.isEmpty || code.isEmpty)
                Button("Test connection") { Task { await companion.connect() } }
            }
            if let info = companion.info {
                Section("Connected host") {
                    LabeledContent("Hostname", value: info.hostname)
                    LabeledContent("OS", value: "\(info.os) \(info.osVersion)")
                    LabeledContent("Architecture", value: info.arch)
                    LabeledContent("Companion", value: info.companionVersion)
                    LabeledContent("Shell", value: info.shellEnabled ? "enabled" : "disabled")
                    ForEach(info.allowedRoots, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.textDim) }
                }
            }
            if let s = status ?? companion.lastError {
                Section { Text(s).font(.caption).foregroundStyle(Theme.textDim) }
            }
            Section("How it works") {
                Text("""
                The companion is a small signed daemon you run on your macOS, Windows or Linux machine. \
                It exposes a local HTTP API protected by a pre-shared key created during pairing. \
                Every filesystem root and every shell command must be explicitly allow-listed on the computer, \
                and destructive commands ask for confirmation on both the desktop and the phone. \
                Source and install scripts live in the Companion/ folder of the project.
                """)
                .font(.caption).foregroundStyle(Theme.textDim)
            }
            Section {
                Button("Disconnect", role: .destructive) {
                    companion.disconnect(); KeychainStore.delete(.companionKey)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Computer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
