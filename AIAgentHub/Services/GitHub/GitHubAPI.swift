import Foundation

struct GHUser: Codable, Hashable { let login: String; var name: String?; var avatarUrl: String?
    enum CodingKeys: String, CodingKey { case login, name; case avatarUrl = "avatar_url" } }

struct GHRepo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    var descriptionText: String?
    var defaultBranch: String
    var isPrivate: Bool
    var stargazersCount: Int?
    var language: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, language
        case fullName = "full_name"
        case descriptionText = "description"
        case defaultBranch = "default_branch"
        case isPrivate = "private"
        case stargazersCount = "stargazers_count"
        case updatedAt = "updated_at"
    }
}

struct GHContent: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let type: String   // file | dir
    var size: Int64?
    var sha: String?
    var content: String?
    var encoding: String?
    var id: String { path }
    var isDirectory: Bool { type == "dir" }

    var decodedText: String? {
        guard let content, encoding == "base64" else { return content }
        let cleaned = content.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct GHRef: Codable { let ref: String; let object: GHRefObject }
struct GHRefObject: Codable { let sha: String }
struct GHCommitResponse: Codable { let content: GHContent?; let commit: GHCommitMeta? }
struct GHCommitMeta: Codable { let sha: String?; var message: String?; var htmlUrl: String?
    enum CodingKeys: String, CodingKey { case sha, message; case htmlUrl = "html_url" } }
struct GHPullRequest: Codable, Identifiable {
    let number: Int
    let title: String
    let htmlUrl: String
    var id: Int { number }
    enum CodingKeys: String, CodingKey { case number, title; case htmlUrl = "html_url" }
}

enum GHError: LocalizedError {
    case noToken
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "Connect a GitHub personal access token in Settings first."
        case .http(let c, let b): return "GitHub API error \(c): \(b)"
        case .decoding(let d): return "Unexpected GitHub response: \(d)"
        }
    }
}

/// Real GitHub REST v3 client (token auth, stored in Keychain).
actor GitHubAPI {

    static let shared = GitHubAPI()
    private let base = URL(string: "https://api.github.com")!
    private let session = URLSession.shared

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Any? = nil) throws -> URLRequest {
        guard let token = KeychainStore.get(.githubToken), !token.isEmpty else { throw GHError.noToken }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("AIAgentHub/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GHError.http(code, String(data: data.prefix(400), encoding: .utf8) ?? "")
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw GHError.decoding(String(describing: error)) }
    }

    // MARK: - Endpoints

    func currentUser() async throws -> GHUser {
        try await send(request("user"), as: GHUser.self)
    }

    func repositories(page: Int = 1) async throws -> [GHRepo] {
        try await send(request("user/repos", query: [
            .init(name: "per_page", value: "100"),
            .init(name: "page", value: String(page)),
            .init(name: "sort", value: "updated")
        ]), as: [GHRepo].self)
    }

    func contents(owner: String, repo: String, path: String = "", ref: String? = nil) async throws -> [GHContent] {
        var query: [URLQueryItem] = []
        if let ref { query.append(.init(name: "ref", value: ref)) }
        let req = try request("repos/\(owner)/\(repo)/contents/\(path)", query: query)
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GHError.http(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        if let many = try? decoder.decode([GHContent].self, from: data) { return many }
        if let one = try? decoder.decode(GHContent.self, from: data) { return [one] }
        throw GHError.decoding("contents")
    }

    func fileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String {
        let items = try await contents(owner: owner, repo: repo, path: path, ref: ref)
        guard let f = items.first, let text = f.decodedText else { throw GHError.decoding("file is binary or empty") }
        return text
    }

    func branchSHA(owner: String, repo: String, branch: String) async throws -> String {
        try await send(request("repos/\(owner)/\(repo)/git/ref/heads/\(branch)"), as: GHRef.self).object.sha
    }

    @discardableResult
    func createBranch(owner: String, repo: String, newBranch: String, fromBranch: String) async throws -> String {
        let sha = try await branchSHA(owner: owner, repo: repo, branch: fromBranch)
        let req = try request("repos/\(owner)/\(repo)/git/refs", method: "POST",
                              body: ["ref": "refs/heads/\(newBranch)", "sha": sha])
        _ = try await send(req, as: GHRef.self)
        return sha
    }

    /// Create or update a file (this is a real commit on the branch).
    @discardableResult
    func putFile(owner: String, repo: String, path: String, content: String,
                 message: String, branch: String) async throws -> GHCommitResponse {
        var existingSHA: String?
        if let items = try? await contents(owner: owner, repo: repo, path: path, ref: branch) {
            existingSHA = items.first(where: { $0.path == path })?.sha
        }
        var body: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": branch
        ]
        if let existingSHA { body["sha"] = existingSHA }
        let req = try request("repos/\(owner)/\(repo)/contents/\(path)", method: "PUT", body: body)
        return try await send(req, as: GHCommitResponse.self)
    }

    func createPullRequest(owner: String, repo: String, title: String, head: String,
                           base: String, body: String) async throws -> GHPullRequest {
        let req = try request("repos/\(owner)/\(repo)/pulls", method: "POST", body: [
            "title": title, "head": head, "base": base, "body": body
        ])
        return try await send(req, as: GHPullRequest.self)
    }

    func deleteFile(owner: String, repo: String, path: String, message: String, branch: String, sha: String) async throws {
        guard !sha.isEmpty else { return }
        let req = try request("repos/\(owner)/\(repo)/contents/\(path)", method: "DELETE", body: [
            "message": message,
            "sha": sha,
            "branch": branch
        ])
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GHError.http(code, String(data: data.prefix(400), encoding: .utf8) ?? "")
        }
    }

    func compare(owner: String, repo: String, base: String, head: String) async throws -> String {
        guard let token = KeychainStore.get(.githubToken) else { throw GHError.noToken }
        var req = URLRequest(url: base_url(owner: owner, repo: repo, base: base, head: head))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3.diff", forHTTPHeaderField: "Accept")
        req.setValue("AIAgentHub/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GHError.http(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func base_url(owner: String, repo: String, base: String, head: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/compare/\(base)...\(head)")!
    }

    func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GHRepo {
        let req = try request("user/repos", method: "POST", body: [
            "name": name,
            "description": description,
            "private": isPrivate
        ] as [String : Any])
        return try await send(req, as: GHRepo.self)
    }

    func issues(owner: String, repo: String) async throws -> [GHIssue] {
        try await send(request("repos/\(owner)/\(repo)/issues", query: [.init(name: "state", value: "open"), .init(name: "per_page", value: "20")]), as: [GHIssue].self)
    }
}

struct GHIssue: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    var body: String?
    var state: String?
    var htmlUrl: String?
    enum CodingKeys: String, CodingKey { case id, number, title, body, state; case htmlUrl = "html_url" }
}
