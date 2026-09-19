import Foundation
import Combine

/// Persistent registry of downloaded models plus their runtime state.
@MainActor
final class ModelLibrary: ObservableObject {

    static let shared = ModelLibrary()

    @Published private(set) var models: [LocalModel] = []
    @Published private(set) var statuses: [UUID: LocalModelStatus] = [:]
    @Published var sort: LocalModelSort = .recent
    @Published private(set) var freeDiskBytes: Int64 = DeviceCapabilities.freeDiskBytes
    @Published private(set) var usedBytes: Int64 = 0

    private let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("models.json")
    }()

    init() {
        load()
        refreshDisk()
        DownloadManager.shared.onCompleted = { [weak self] info, url in
            self?.register(from: info, at: url)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([LocalModel].self, from: data) else { return }
        models = decoded
        revalidate()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func revalidate() {
        for m in models {
            let url = ModelStorage.location(repoId: m.repoId, revision: m.revision, file: m.fileName)
            if !ModelStorage.exists(url) {
                statuses[m.id] = .missingFile
            } else if statuses[m.id] == nil || statuses[m.id] == .missingFile {
                statuses[m.id] = DeviceCapabilities.evaluate(model: m).canRun ? .ready : .incompatible
            }
        }
        refreshDisk()
    }

    func refreshDisk() {
        freeDiskBytes = DeviceCapabilities.freeDiskBytes
        usedBytes = ModelStorage.totalUsedBytes()
    }

    // MARK: - Registration

    /// Metadata captured at download time so the local card stays informative offline.
    var pendingMetadata: [String: (arch: String?, license: String?, params: Int?, pipeline: String?)] = [:]

    func note(repoId: String, arch: String?, license: String?, params: Int?, pipeline: String?) {
        pendingMetadata[repoId] = (arch, license, params, pipeline)
    }

    func register(from info: DownloadTaskInfo, at url: URL) {
        let meta = pendingMetadata[info.repoId]
        let format = ModelFormat.detect(fileName: info.fileName)
        var model = LocalModel(repoId: info.repoId,
                               fileName: info.fileName,
                               revision: info.revision,
                               sizeBytes: ModelStorage.size(of: url),
                               format: format,
                               quantization: Quantization.detect(in: info.fileName),
                               parameterCount: meta?.params,
                               architecture: meta?.arch,
                               license: meta?.license,
                               pipelineTag: meta?.pipeline)
        if let existing = models.firstIndex(where: { $0.repoId == model.repoId && $0.fileName == model.fileName && $0.revision == model.revision }) {
            model.id = models[existing].id
            model.isFavorite = models[existing].isFavorite
            models[existing] = model
        } else {
            models.append(model)
        }
        statuses[model.id] = DeviceCapabilities.evaluate(model: model).canRun ? .ready : .incompatible
        save()
        refreshDisk()
    }

    func isDownloaded(repoId: String, file: String, revision: String = "main") -> Bool {
        models.contains { $0.repoId == repoId && $0.fileName == file && $0.revision == revision }
    }

    // MARK: - Mutation

    func delete(_ model: LocalModel) {
        let url = ModelStorage.location(repoId: model.repoId, revision: model.revision, file: model.fileName)
        try? ModelStorage.delete(url)
        models.removeAll { $0.id == model.id }
        statuses.removeValue(forKey: model.id)
        save()
        refreshDisk()
    }

    func toggleFavorite(_ model: LocalModel) {
        guard let i = models.firstIndex(where: { $0.id == model.id }) else { return }
        models[i].isFavorite.toggle()
        save()
    }

    func setStatus(_ status: LocalModelStatus, for id: UUID) { statuses[id] = status }

    func markUsed(_ id: UUID) {
        guard let i = models.firstIndex(where: { $0.id == id }) else { return }
        models[i].lastUsedAt = Date()
        save()
    }

    func status(for model: LocalModel) -> LocalModelStatus {
        statuses[model.id] ?? .ready
    }

    func model(withId id: UUID) -> LocalModel? { models.first { $0.id == id } }

    // MARK: - Queries

    var sorted: [LocalModel] {
        switch sort {
        case .recent: return models.sorted { $0.downloadedAt > $1.downloadedAt }
        case .name: return models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .size: return models.sorted { $0.sizeBytes > $1.sizeBytes }
        case .format: return models.sorted { $0.format.title < $1.format.title }
        }
    }

    var favorites: [LocalModel] { sorted.filter(\.isFavorite) }
    var running: [LocalModel] { sorted.filter { statuses[$0.id] == .running || statuses[$0.id] == .loading } }
}
