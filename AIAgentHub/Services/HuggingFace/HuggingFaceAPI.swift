import Foundation

enum HFError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)
    case unauthorized
    case gated(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .badURL: return "Malformed Hugging Face URL."
        case .http(let code, let body): return "Hugging Face returned HTTP \(code). \(body)"
        case .decoding(let d): return "Could not read the Hugging Face response: \(d)"
        case .unauthorized: return "Your Hugging Face token is missing or invalid. Connect your account in Settings."
        case .gated(let repo): return "\(repo) is a gated repository. Accept its license on huggingface.co with the same account, then retry."
        case .notFound: return "Not found on Hugging Face."
        }
    }
}

/// Real client for the public Hugging Face Hub REST API.
/// Docs: https://huggingface.co/docs/hub/api
actor HuggingFaceAPI {

    static let shared = HuggingFaceAPI()

    private let base = URL(string: "https://huggingface.co")!
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            return Date()
        }
        self.decoder = d
    }

    private var token: String? { KeychainStore.get(.huggingFaceToken) }

    nonisolated func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("AIAgentHub/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let t = KeychainStore.get(.huggingFaceToken), !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func perform(_ request: URLRequest, repoHint: String = "") async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw HFError.unauthorized
        case 403: throw HFError.gated(repoHint.isEmpty ? request.url?.path ?? "repository" : repoHint)
        case 404: throw HFError.notFound
        default:
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw HFError.http(http.statusCode, body)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw HFError.decoding(String(describing: error)) }
    }

    // MARK: - Search

    func searchModels(_ q: HFSearchQuery) async throws -> [HFModelSummary] {
        var comps = URLComponents(url: base.appendingPathComponent("api/models"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(q.limit)),
            .init(name: "sort", value: q.sort.rawValue),
            .init(name: "direction", value: "-1"),
            .init(name: "full", value: "true"),
            .init(name: "config", value: "true")
        ]
        if !q.text.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(.init(name: "search", value: q.text))
        }
        for tag in q.tags { items.append(.init(name: "filter", value: tag)) }
        if let p = q.pipelineTag { items.append(.init(name: "pipeline_tag", value: p)) }
        if let l = q.library { items.append(.init(name: "library", value: l)) }
        if let a = q.author { items.append(.init(name: "author", value: a)) }
        comps.queryItems = items
        guard let url = comps.url else { throw HFError.badURL }
        let data = try await perform(authorizedRequest(url: url))
        return try decode([HFModelSummary].self, from: data)
    }

    // MARK: - Model detail

    func modelDetail(id: String, revision: String = "main") async throws -> HFModelDetail {
        guard var comps = URLComponents(string: "\(base.absoluteString)/api/models/\(id)/revision/\(revision)") else {
            throw HFError.badURL
        }
        comps.queryItems = [.init(name: "blobs", value: "false")]
        guard let url = comps.url else { throw HFError.badURL }
        let data = try await perform(authorizedRequest(url: url), repoHint: id)
        return try decode(HFModelDetail.self, from: data)
    }

    /// Full recursive-ish file tree for a folder inside the repo.
    func tree(id: String, revision: String = "main", path: String = "", recursive: Bool = false) async throws -> [HFTreeEntry] {
        var urlString = "\(base.absoluteString)/api/models/\(id)/tree/\(revision)"
        if !path.isEmpty { urlString += "/\(path)" }
        guard var comps = URLComponents(string: urlString) else { throw HFError.badURL }
        var items = [URLQueryItem(name: "expand", value: "true")]
        if recursive { items.append(.init(name: "recursive", value: "true")) }
        comps.queryItems = items
        guard let url = comps.url else { throw HFError.badURL }
        let data = try await perform(authorizedRequest(url: url), repoHint: id)
        return try decode([HFTreeEntry].self, from: data)
    }

    /// Raw README.md (model card) text.
    func readme(id: String, revision: String = "main") async throws -> String {
        guard let url = URL(string: "\(base.absoluteString)/\(id)/raw/\(revision)/README.md") else { throw HFError.badURL }
        let data = try await perform(authorizedRequest(url: url), repoHint: id)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// HEAD a resolve URL to learn the real content length (LFS aware).
    func fileSize(id: String, revision: String = "main", file: String) async throws -> Int64 {
        let url = Self.resolveURL(repoId: id, revision: revision, file: file)
        var req = authorizedRequest(url: url, method: "HEAD")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return 0 }
        if let linked = http.value(forHTTPHeaderField: "x-linked-size"), let v = Int64(linked) { return v }
        return http.expectedContentLength > 0 ? http.expectedContentLength : 0
    }

    // MARK: - Auth

    func whoAmI() async throws -> HFUser {
        guard token != nil else { throw HFError.unauthorized }
        let url = base.appendingPathComponent("api/whoami-v2")
        let data = try await perform(authorizedRequest(url: url))
        return try decode(HFUser.self, from: data)
    }

    // MARK: - Inference (cloud fallback for agents)

    func chatCompletion(model: String, messages: [[String: String]], temperature: Double, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "https://router.huggingface.co/v1/chat/completions") else { throw HFError.badURL }
        var req = authorizedRequest(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(req, repoHint: model)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw HFError.decoding("Unexpected chat completion payload")
        }
        return content
    }

    // MARK: - URLs

    nonisolated static func resolveURL(repoId: String, revision: String = "main", file: String) -> URL {
        let encoded = file.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repoId)/resolve/\(revision)/\(encoded)?download=true")!
    }
}
