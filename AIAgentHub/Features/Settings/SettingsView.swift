import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @EnvironmentObject var library: ModelLibrary
    @EnvironmentObject var companion: CompanionClient

    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("allowCellularDownloads") private var allowCellular = false
    @AppStorage("openai.baseURL") private var openAIBase = "https://api.openai.com/v1"

    @State private var hfToken = ""
    @State private var openAIKey = ""
    @State private var showHFConnect = false
    @State private var connectError: String?

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Offline Mode") {
                    Toggle("Offline Mode", isOn: $offlineMode)
                    Text("When on, agents must use a downloaded model, inference runs on device, files stay in the app sandbox and task history is never uploaded.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("Downloads") {
                    Toggle("Allow cellular downloads", isOn: $allowCellular)
                    LabeledContent("Free space", value: Fmt.bytes(library.freeDiskBytes))
                    LabeledContent("Used by models", value: Fmt.bytes(library.usedBytes))
                    LabeledContent("Models installed", value: "\(library.models.count)")
                }

                Section("Cloud inference") {
                    TextField("OpenAI-compatible base URL", text: $openAIBase)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("API key", text: $openAIKey)
                    Button("Save key") { KeychainStore.set(openAIKey, for: .openAIKey); openAIKey = "" }
                        .disabled(openAIKey.isEmpty)
                    if KeychainStore.has(.openAIKey) {
                        Button("Remove key", role: .destructive) { KeychainStore.delete(.openAIKey) }
                    }
                }

                Section("💻 Computer companion") {
                    NavigationLink { CompanionView() } label: {
                        HStack {
                            Text("Paired computer")
                            Spacer()
                            Text(companion.isConnected ? (companion.info?.hostname ?? "connected") : "not paired")
                                .foregroundStyle(Theme.textDim).font(.caption)
                        }
                    }
                }

                Section("Device") {
                    LabeledContent("Model", value: DeviceCapabilities.deviceModelIdentifier)
                    LabeledContent("RAM", value: Fmt.bytes(DeviceCapabilities.physicalMemoryBytes))
                    LabeledContent("Model RAM budget", value: Fmt.bytes(DeviceCapabilities.usableMemoryBudgetBytes))
                    LabeledContent("MLX capable", value: DeviceCapabilities.supportsMLX ? "yes" : "no")
                }

                Section("Security") {
                    Button("Erase all stored tokens", role: .destructive) {
                        KeychainStore.wipeAll(); hf.user = nil
                    }
                    Text("Tokens live in the Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly and are never included in backups.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                Section("About") {
                    LabeledContent("AI Agent Hub", value: "1.0.0")
                    Text("Download AI from Hugging Face. Build agents. Create anything.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                    Link("Hugging Face Hub", destination: URL(string: "https://huggingface.co")!)
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
