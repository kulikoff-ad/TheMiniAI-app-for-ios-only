import Foundation

/// A model file that has been downloaded to the device.
struct LocalModel: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Hugging Face repository id, e.g. `Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF`.
    var repoId: String
    /// Path of the file inside the repository.
    var fileName: String
    var revision: String = "main"
    var sizeBytes: Int64
    var format: ModelFormat
    var quantization: String?
    var parameterCount: Int?
    var architecture: String?
    var license: String?
    var pipelineTag: String?
    var downloadedAt: Date = Date()
    var isFavorite: Bool = false
    var lastUsedAt: Date?

    var displayName: String {
        let base = (fileName as NSString).lastPathComponent
        return base.isEmpty ? repoId : base
    }

    var runtime: InferenceRuntime { format.runtime }

    /// Relative location under Application Support/Models.
    var relativePath: String {
        "\(repoId.replacingOccurrences(of: "/", with: "__"))/\(revision)/\(fileName)"
    }

    var parameterDescription: String? {
        guard let p = parameterCount, p > 0 else { return nil }
        let b = Double(p)
        if b >= 1e9 { return String(format: "%.1fB params", b / 1e9) }
        if b >= 1e6 { return String(format: "%.0fM params", b / 1e6) }
        return "\(p) params"
    }
}

enum LocalModelStatus: String, Codable, Hashable {
    case ready
    case running
    case loading
    case incompatible
    case missingFile

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .running: return "Running"
        case .loading: return "Loading"
        case .incompatible: return "Incompatible"
        case .missingFile: return "File missing"
        }
    }
}

enum LocalModelSort: String, CaseIterable, Identifiable, Codable {
    case recent, name, size, format
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "Recently added"
        case .name: return "Name"
        case .size: return "Size"
        case .format: return "Format"
        }
    }
}

// MARK: - Downloads

enum DownloadState: String, Codable, Hashable {
    case queued, downloading, paused, completed, failed, cancelled

    var title: String {
        switch self {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct DownloadTaskInfo: Codable, Identifiable, Hashable {
    var id: String { "\(repoId)@\(revision)/\(fileName)" }
    var repoId: String
    var revision: String
    var fileName: String
    var totalBytes: Int64
    var receivedBytes: Int64 = 0
    var state: DownloadState = .queued
    var errorMessage: String?
    var startedAt: Date = Date()

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }
}
