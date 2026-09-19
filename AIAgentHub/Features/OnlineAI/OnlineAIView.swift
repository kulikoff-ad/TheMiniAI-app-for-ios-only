import SwiftUI

/// 🌐 Online AI — работает независимо от локальных моделей. Provider Manager + выбор Local / Online / Auto.
struct OnlineAIView: View {
    @EnvironmentObject var online: OnlineProviderStore
    @EnvironmentObject var library: ModelLibrary
    @State private var showAdd = false
    @State private var editing: OnlineProvider?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modeCard
                providersCard
                howItWorks
            }.padding(16)
        }
        .screenBackground()
        .navigationTitle("🌐 Online AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ProviderEditSheet(provider: nil) }
        .sheet(item: $editing) { p in ProviderEditSheet(provider: p) }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Inference mode")
            Picker("Mode", selection: $online.mode) {
                ForEach(OnlineMode.allCases) { m in
                    Label(m.title, systemImage: m.icon).tag(m)
                }
            }.pickerStyle(.segmented)
            Group {
                switch online.mode {
                case .local:
                    Label("Only downloaded models will be used. Network calls are blocked.", systemImage: "iphone")
                case .online:
                    Label("Only cloud providers will be used. Local models are ignored.", systemImage: "cloud")
                case .auto:
                    Label("Auto — the app picks the best available option for the task (local if installed and compatible, otherwise the selected online provider).", systemImage: "wand.and.stars")
                }
            }.font(.caption).foregroundStyle(Theme.textDim)
            if online.mode == .local && library.models.isEmpty {
                Text("No local models installed — download a GGUF in 📱 Phone AI or 🤗 Hugging Face first.")
                    .font(.caption).foregroundStyle(Theme.warn)
            }
        }.card()
    }

    private var providersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "AI Provider Manager")
                Spacer()
                Text("\(online.providers.count) providers").font(.caption2).foregroundStyle(Theme.textDim)
            }
            ForEach(online.providers) { p in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if online.selectedId == p.id { Pill(text: "Selected", color: Theme.good) }
                        }
                        Text(p.baseURL).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
                        Text("Model: \(p.model)").font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
                        HStack(spacing: 6) {
                            Pill(text: p.displayHost, color: Theme.accent2)
                            if OnlineProviderStore.shared.getKey(for: p) != nil {
                                Pill(text: "key stored", color: Theme.good, icon: "key.fill")
                            } else {
                                Pill(text: "no key", color: Theme.warn, icon: "key.slash")
                            }
                        }
                    }
                    Spacer()
                    Menu {
                        Button { online.selectedId = p.id } label: { Label("Select", systemImage: "checkmark") }
                        Button { editing = p } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { online.delete(p) } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textDim)
                    }
                }
                .padding(12)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(online.selectedId == p.id ? Theme.good.opacity(0.5) : Theme.stroke))
                .onTapGesture { online.selectedId = p.id }
            }
            Button { showAdd = true } label: {
                Label("Add provider", systemImage: "plus.circle").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(Theme.accent2)
        }.card()
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "How keys are stored")
            Text("API keys are saved in the iOS Keychain per provider (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) and never leave the device except to the provider's own host. Use Custom API for any OpenAI-compatible endpoint (Groq, Together, local LLM server, etc.).")
                .font(.caption).foregroundStyle(Theme.textDim)
            NavigationLink { OnlineHelpView() } label: {
                Label("Learn about Custom API", systemImage: "questionmark.circle").font(.caption)
            }
        }.card()
    }
}

struct ProviderEditSheet: View {
    var provider: OnlineProvider?
    @EnvironmentObject var online: OnlineProviderStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var apiKey: String = ""
    @State private var showKey = false

    var isNew: Bool { provider == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("Name", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Model id", text: $model)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Text("Examples: https://api.openai.com/v1 / https://router.huggingface.co/v1 / http://192.168.1.50:8000/v1").font(.caption2).foregroundStyle(Theme.textDim)
                }
                Section("API key") {
                    HStack {
                        Group {
                            if showKey { TextField("sk-…", text: $apiKey) } else { SecureField("sk-…", text: $apiKey) }
                        }.autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                    }
                    if let p = provider, OnlineProviderStore.shared.getKey(for: p) != nil {
                        Text("A key is already stored in Keychain. Entering a new one will overwrite it.").font(.caption2).foregroundStyle(Theme.textDim)
                    } else {
                        Text("Stored in iOS Keychain — never in plain text.").font(.caption2).foregroundStyle(Theme.textDim)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Add Provider" : "Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty || baseURL.isEmpty || model.isEmpty)
                }
            }
            .onAppear {
                if let p = provider {
                    name = p.name; baseURL = p.baseURL; model = p.model
                    apiKey = OnlineProviderStore.shared.getKey(for: p) ?? ""
                }
            }
        }
    }

    private func save() {
        var p = provider ?? OnlineProvider(name: name, baseURL: baseURL, model: model, keychainKey: "online.provider.\(UUID().uuidString.prefix(8))")
        p.name = name; p.baseURL = baseURL; p.model = model
        if isNew {
            online.add(p)
            if !apiKey.isEmpty { online.setKey(apiKey, for: p) }
        } else {
            online.update(p)
            if !apiKey.isEmpty { online.setKey(apiKey, for: p) }
            else { KeychainStore.deleteGeneric(key: p.keychainKey) }
        }
        dismiss()
    }
}

struct OnlineHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Provider tree").font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Online AI").font(.subheadline.weight(.semibold))
                    Text("├── Provider 1 — Hugging Face Router").font(Theme.mono)
                    Text("├── Provider 2 — OpenAI").font(Theme.mono)
                    Text("├── Provider 3 — Groq / Together / Mistral …").font(Theme.mono)
                    Text("└── Custom API — any OpenAI-compatible base URL").font(Theme.mono)
                }.card()
                Text("All providers speak the same OpenAI-compatible `/v1/chat/completions` shape. The app sends `{model, messages, temperature, max_tokens}` and reads `choices[0].message.content`. Put your own server URL in Custom API to use a local LLM (e.g. Ollama with OpenAI shim, vLLM, LocalAI) without exposing keys to the internet.").font(.caption).foregroundStyle(Theme.textDim).card()
                Text("Local / Online / Auto").font(.headline)
                Text("Settings → Online AI → Mode. Auto means: if the agent is bound to a downloaded model and that model is compatible, use it; otherwise use the selected Online provider. Offline Mode (global) forces Local regardless of this setting.").font(.caption).foregroundStyle(Theme.textDim).card()
            }.padding(16)
        }.screenBackground().navigationTitle("Online AI Help").navigationBarTitleDisplayMode(.inline)
    }
}
