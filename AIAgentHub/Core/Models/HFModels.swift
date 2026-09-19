import Foundation

// MARK: - Hugging Face API DTOs

struct HFModelSummary: Codable, Identifiable, Hashable {
    let id: String
    var author: String?
    var pipelineTag: String?
    var libraryName: String?
    var tags: [String]?
    var downloads: Int?
    var likes: Int?
    var lastModified: Date?
    var gated: HFGated?
    var isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case id, author, tags, downloads, likes
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case lastModified
        case gated
        case isPrivate = "private"
    }

    var name: String { id.split(separator: "/").last.map(String.init) ?? id }
    var owner: String { author ?? id.split(separator: "/").first.map(String.init) ?? "—" }
    var hfURL: URL { URL(string: "https://huggingface.co/\(id)")! }

    /// Best-effort detection of formats advertised by tags.
    var advertisedFormats: [ModelFormat] {
        let t = (tags ?? []).map { $0.lowercased() }
        var out: Set<ModelFormat> = []
        if t.contains("gguf") { out.insert(.gguf) }
        if t.contains("safetensors") { out.insert(.safetensors) }
        if t.contains("onnx") { out.insert(.onnx) }
        if t.contains("coreml") || t.contains("core-ml") { out.insert(.coreml) }
        if t.contains("mlx") { out.insert(.mlx) }
        if t.contains("tflite") { out.insert(.tflite) }
        return out.sorted { $0.rawValue < $1.rawValue }
    }
}

enum HFGated: Codable, Hashable {
    case no
    case auto
    case manual

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = b ? .manual : .no; return }
        let s = (try? c.decode(String.self))?.lowercased() ?? "false"
        switch s {
        case "auto": self = .auto
        case "manual", "true": self = .manual
        default: self = .no
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .no: try c.encode(false)
        case .auto: try c.encode("auto")
        case .manual: try c.encode("manual")
        }
    }

    var isGated: Bool { self != .no }
}

struct HFModelDetail: Codable, Identifiable, Hashable {
    let id: String
    var author: String?
    var sha: String?
    var pipelineTag: String?
    var libraryName: String?
    var tags: [String]?
    var downloads: Int?
    var likes: Int?
    var lastModified: Date?
    var gated: HFGated?
    var cardData: HFCardData?
    var config: HFConfig?
    var siblings: [HFSibling]?
    var safetensors: HFSafetensorsInfo?

    enum CodingKeys: String, CodingKey {
        case id, author, sha, tags, downloads, likes, lastModified, gated, siblings, safetensors, config
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case cardData
    }

    var license: String? {
        if let l = cardData?.license, !l.isEmpty { return l }
        return tags?.first(where: { $0.hasPrefix("license:") })?.replacingOccurrences(of: "license:", with: "")
    }

    var architecture: String? {
        config?.architectures?.first ?? config?.modelType
    }

    var parameterCount: Int? {
        guard let total = safetensors?.total, total > 0 else { return nil }
        return total
    }

    var languages: [String] {
        let fromCard = cardData?.language ?? []
        let fromTags = (tags ?? []).filter { $0.count == 2 && $0.lowercased() == $0 }
        return Array(Set(fromCard + fromTags)).sorted()
    }

    var hfURL: URL { URL(string: "https://huggingface.co/\(id)")! }
}

struct HFCardData: Codable, Hashable {
    var license: String?
    var language: [String]?
    var tags: [String]?
    var baseModel: String?

    enum CodingKeys: String, CodingKey {
        case license, tags
        case language
        case baseModel = "base_model"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        license = try? c.decodeIfPresent(String.self, forKey: .license)
        tags = try? c.decodeIfPresent([String].self, forKey: .tags)
        if let arr = try? c.decodeIfPresent([String].self, forKey: .language) {
            language = arr
        } else if let one = try? c.decodeIfPresent(String.self, forKey: .language) {
            language = [one]
        } else {
            language = nil
        }
        if let b = try? c.decodeIfPresent(String.self, forKey: .baseModel) {
            baseModel = b
        } else if let arr = try? c.decodeIfPresent([String].self, forKey: .baseModel) {
            baseModel = arr.first
        } else {
            baseModel = nil
        }
    }
}

struct HFConfig: Codable, Hashable {
    var modelType: String?
    var architectures: [String]?
    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case architectures
    }
}

struct HFSafetensorsInfo: Codable, Hashable {
    var total: Int?
    var parameters: [String: Int]?
}

struct HFSibling: Codable, Hashable, Identifiable {
    let rfilename: String
    var id: String { rfilename }
}

/// Entry returned by the `/api/models/{id}/tree/{rev}` endpoint.
struct HFTreeEntry: Codable, Hashable, Identifiable {
    let type: String          // "file" | "directory"
    let path: String
    var size: Int64?
    var oid: String?
    var lfs: HFLFS?

    var id: String { path }
    var isDirectory: Bool { type == "directory" }
    var byteSize: Int64 { lfs?.size ?? size ?? 0 }
    var format: ModelFormat { ModelFormat.detect(fileName: path) }
    var quantization: String? { Quantization.detect(in: path) }
}

struct HFLFS: Codable, Hashable {
    var oid: String?
    var size: Int64?
}

struct HFUser: Codable, Hashable {
    let name: String
    var fullname: String?
    var email: String?
    var avatarUrl: String?
}

// MARK: - Search parameters

enum HFSortOption: String, CaseIterable, Identifiable, Codable {
    case trending = "trendingScore"
    case downloads
    case likes
    case lastModified

    var id: String { rawValue }
    var title: String {
        switch self {
        case .trending: return "Trending"
        case .downloads: return "Downloads"
        case .likes: return "Likes"
        case .lastModified: return "Recently updated"
        }
    }
}

struct HFSearchQuery: Equatable {
    var text: String = ""
    var tags: [String] = []
    var pipelineTag: String? = nil
    var library: String? = nil
    var author: String? = nil
    var sort: HFSortOption = .trending
    var limit: Int = 40
}
