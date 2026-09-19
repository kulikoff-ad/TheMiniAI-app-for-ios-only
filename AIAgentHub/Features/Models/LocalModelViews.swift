import SwiftUI

struct LocalModelListView: View {
    let models: [LocalModel]
    var showSort: Bool = false
    var emptyMessage: String = "Download a model from the Hugging Face tab and it will appear here."
    @EnvironmentObject var library: ModelLibrary
    @EnvironmentObject var downloads: DownloadManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if showSort {
                    HStack {
                        Text("Free: \(Fmt.bytes(library.freeDiskBytes)) · Used: \(Fmt.bytes(library.usedBytes))")
                            .font(.caption2).foregroundStyle(Theme.textDim)
                        Spacer()
                        Picker("Sort", selection: $library.sort) {
                            ForEach(LocalModelSort.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)
                    }
                }
                ForEach(downloads.active) { DownloadRow(info: $0) }
                if models.isEmpty {
                    EmptyStateView(icon: "tray", title: "Nothing here yet", message: emptyMessage).card()
                }
                ForEach(models) { model in
                    NavigationLink { LocalModelDetailView(model: model) } label: { LocalModelRow(model: model) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .refreshable { library.revalidate() }
    }
}

struct LocalModelRow: View {
    let model: LocalModel
    @EnvironmentObject var library: ModelLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.repoId).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                Spacer()
                StatusBadge(status: library.status(for: model))
            }
            HStack(spacing: 6) {
                Pill(text: model.format.title, color: Theme.accent2, icon: model.format.symbol)
                if let q = model.quantization { Pill(text: q, color: Theme.good) }
                Pill(text: Fmt.bytes(model.sizeBytes), color: Theme.textDim)
                if model.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.accent) }
            }
            HStack(spacing: 14) {
                Label(model.runtime.title, systemImage: "bolt")
                if let p = model.parameterDescription { Label(p, systemImage: "number") }
            }
            .font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct StatusBadge: View {
    let status: LocalModelStatus
    var body: some View {
        let color: Color = {
            switch status {
            case .ready: return Theme.good
            case .running: return Theme.accent2
            case .loading: return Theme.warn
            case .incompatible, .missingFile: return Theme.bad
            }
        }()
        return Pill(text: status.title, color: color)
    }
}

struct LocalModelDetailView: View {
    let model: LocalModel
    @EnvironmentObject var library: ModelLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var showDelete = false
    @State private var loadError: String?
    @State private var isStarting = false
    @State private var testOutput: String = ""

    private var compat: DeviceCapabilities.Compatibility { DeviceCapabilities.evaluate(model: model) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.displayName).font(.headline)
                    Text(model.repoId).font(.caption).foregroundStyle(Theme.textDim)
                    HStack(spacing: 6) {
                        Pill(text: model.format.title, color: Theme.accent2, icon: model.format.symbol)
                        StatusBadge(status: library.status(for: model))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Details")
                    row("Size", Fmt.bytes(model.sizeBytes))
                    row("Format", model.format.title)
                    row("Quantization", model.quantization ?? "—")
                    row("Parameters", model.parameterDescription ?? "unknown")
                    row("Architecture", model.architecture ?? "—")
                    row("License", model.license ?? "—")
                    row("Runtime", model.runtime.title)
                    row("Downloaded", Fmt.ago(model.downloadedAt))
                    row("Estimated RAM", Fmt.bytes(compat.estimatedMemoryBytes))
                }
                .card()

                if !compat.canRun {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("This model cannot be loaded on this device.", systemImage: "xmark.octagon.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.bad)
                        Text(compat.reason ?? "").font(.caption).foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                if let loadError {
                    Text(loadError).font(.caption).foregroundStyle(Theme.bad).card()
                }

                if !testOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Output")
                        Text(testOutput).font(Theme.mono).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await start() }
                    } label: {
                        Label(isStarting ? "Starting…" : "Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.good)
                    .disabled(!compat.canRun || isStarting)

                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Theme.bad)
                }

                Button {
                    library.toggleFavorite(model)
                } label: {
                    Label(model.isFavorite ? "Remove from favorites" : "Add to favorites",
                          systemImage: model.isFavorite ? "star.slash" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete file", role: .destructive) { library.delete(model); dismiss() }
        } message: {
            Text("Frees \(Fmt.bytes(model.sizeBytes)) on this device.")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.caption).foregroundStyle(Theme.textDim); Spacer()
                 Text(v).font(.caption.weight(.medium)) }
    }

    private func start() async {
        isStarting = true
        loadError = nil
        library.setStatus(.loading, for: model.id)
        do {
            let engine = try InferenceEngineFactory.make(for: model)
            try await engine.load()
            library.setStatus(.running, for: model.id)
            library.markUsed(model.id)
            let text = try await engine.complete(
                messages: [.init(role: .user, content: "Say hello in one short sentence.")],
                temperature: 0.7, maxTokens: 64) { _ in }
            testOutput = text
        } catch {
            loadError = error.localizedDescription
            library.setStatus(compat.canRun ? .ready : .incompatible, for: model.id)
        }
        isStarting = false
    }
}
