import Foundation
import Combine

@MainActor
final class HuggingFaceStore: ObservableObject {

    static let shared = HuggingFaceStore()

    @Published var query = HFSearchQuery()
    @Published private(set) var results: [HFModelSummary] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    @Published var user: HFUser?
    @Published var isCheckingAuth = false

    var isConnected: Bool { KeychainStore.has(.huggingFaceToken) }

    /// Popular filter chips.
    static let formatFilters: [(String, String)] = [
        ("GGUF", "gguf"), ("SafeTensors", "safetensors"), ("ONNX", "onnx"),
        ("Core ML", "coreml"), ("MLX", "mlx"), ("TFLite", "tflite")
    ]

    static let taskFilters: [String] = [
        "text-generation", "text2text-generation", "feature-extraction",
        "automatic-speech-recognition", "image-classification", "text-to-image",
        "translation", "summarization", "question-answering", "fill-mask"
    ]

    private var searchTask: Task<Void, Never>?

    func search(debounced: Bool = true) {
        searchTask?.cancel()
        let snapshot = query
        searchTask = Task {
            if debounced { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            await performSearch(snapshot)
        }
    }

    private func performSearch(_ q: HFSearchQuery) async {
        isSearching = true
        errorMessage = nil
        do {
            let r = try await HuggingFaceAPI.shared.searchModels(q)
            guard !Task.isCancelled else { return }
            results = r
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription; results = [] }
        }
        isSearching = false
    }

    func toggleTag(_ tag: String) {
        if let i = query.tags.firstIndex(of: tag) { query.tags.remove(at: i) } else { query.tags.append(tag) }
        search(debounced: false)
    }

    func setPipeline(_ tag: String?) {
        query.pipelineTag = (query.pipelineTag == tag) ? nil : tag
        search(debounced: false)
    }

    func clearFilters() {
        query.tags = []
        query.pipelineTag = nil
        query.library = nil
        query.author = nil
        search(debounced: false)
    }

    // MARK: - Auth

    func refreshUser() async {
        guard isConnected else { user = nil; return }
        isCheckingAuth = true
        defer { isCheckingAuth = false }
        do { user = try await HuggingFaceAPI.shared.whoAmI() }
        catch { user = nil; errorMessage = error.localizedDescription }
    }

    func connect(token: String) async -> Bool {
        KeychainStore.set(token.trimmingCharacters(in: .whitespacesAndNewlines), for: .huggingFaceToken)
        await refreshUser()
        if user == nil { KeychainStore.delete(.huggingFaceToken); return false }
        return true
    }

    func disconnect() {
        KeychainStore.delete(.huggingFaceToken)
        user = nil
    }
}

/// Detail view model — model card, files, download orchestration.
@MainActor
final class ModelDetailViewModel: ObservableObject {

    let repoId: String
    @Published var detail: HFModelDetail?
    @Published var readme: String = ""
    @Published var files: [HFTreeEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFiles: Set<String> = []

    init(repoId: String) { self.repoId = repoId }

    var revision: String { "main" }

    var totalSelectedBytes: Int64 {
        files.filter { selectedFiles.contains($0.path) }.reduce(0) { $0 + $1.byteSize }
    }

    var repoTotalBytes: Int64 { files.reduce(0) { $0 + $1.byteSize } }

    var runnableFiles: [HFTreeEntry] {
        files.filter { $0.format.runtime.runsOnDevice }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        async let d = try? HuggingFaceAPI.shared.modelDetail(id: repoId)
        async let t = try? HuggingFaceAPI.shared.tree(id: repoId, recursive: true)
        async let r = try? HuggingFaceAPI.shared.readme(id: repoId)
        detail = await d
        files = (await t ?? []).filter { !$0.isDirectory }.sorted { $0.byteSize > $1.byteSize }
        readme = await r ?? ""
        if detail == nil && files.isEmpty {
            errorMessage = "Could not load \(repoId). It may be gated or private — connect your Hugging Face account."
        }
        // Preselect the smallest runnable artefact to guide the user.
        if selectedFiles.isEmpty, let smallest = runnableFiles.min(by: { $0.byteSize < $1.byteSize }) {
            selectedFiles.insert(smallest.path)
        }
        isLoading = false
    }

    func toggle(_ file: HFTreeEntry) {
        if selectedFiles.contains(file.path) { selectedFiles.remove(file.path) }
        else { selectedFiles.insert(file.path) }
    }

    /// Warning shown before starting a download, nil when everything is fine.
    var downloadWarning: String? {
        guard totalSelectedBytes > 0 else { return nil }
        return DeviceCapabilities.evaluateBeforeDownload(sizeBytes: totalSelectedBytes)
    }

    var canDownload: Bool {
        !selectedFiles.isEmpty && totalSelectedBytes < DeviceCapabilities.freeDiskBytes
    }

    func startDownload() {
        ModelLibrary.shared.note(repoId: repoId,
                                 arch: detail?.architecture,
                                 license: detail?.license,
                                 params: detail?.parameterCount,
                                 pipeline: detail?.pipelineTag)
        for path in selectedFiles {
            let size = files.first(where: { $0.path == path })?.byteSize ?? 0
            DownloadManager.shared.start(repoId: repoId, revision: revision, file: path, expectedSize: size)
        }
    }
}
