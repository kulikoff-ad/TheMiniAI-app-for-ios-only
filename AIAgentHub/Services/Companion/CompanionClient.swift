import Foundation
import Combine

/// Talks to the AI Agent Hub Companion running on the user's macOS / Windows / Linux machine.
/// Transport: HTTPS-capable JSON over the local network, authenticated with a pre-shared key
/// generated during pairing and stored in the iOS Keychain. The phone never gets implicit access:
/// every command must be inside the allow-list the desktop app enforces.
@MainActor
final class CompanionClient: ObservableObject {

    static let shared = CompanionClient()

    struct HostInfo: Codable, Hashable {
        var hostname: String
        var os: String            // macOS | Windows | Linux
        var osVersion: String
        var arch: String
        var companionVersion: String
        var allowedRoots: [String]
        var shellEnabled: Bool
    }

    struct CommandResult: Codable, Hashable {
        var exitCode: Int
        var stdout: String
        var stderr: String
    }

    enum CompanionError: LocalizedError {
        case notConfigured
        case notAuthorized
        case transport(String)
        case remote(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "No companion host configured. Pair a computer in the Computer tab first."
            case .notAuthorized: return "Computer control is not allowed for this agent. Enable it in the agent's permissions."
            case .transport(let m): return "Cannot reach the companion: \(m)"
            case .remote(let c, let m): return "Companion refused the request (\(c)): \(m)"
            }
        }
    }

    @AppStorageBacked("companion.host", default: "") var host: String
    @Published var isConnected = false
    @Published var info: HostInfo?
    @Published var lastError: String?

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    private var baseURL: URL? {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return nil }
        return URL(string: h.contains("://") ? h : "http://\(h)")
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        guard let baseURL else { throw CompanionError.notConfigured }
        guard let key = KeychainStore.get(.companionKey), !key.isEmpty else { throw CompanionError.notConfigured }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw CompanionError.remote(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as CompanionError {
            throw e
        } catch {
            throw CompanionError.transport(error.localizedDescription)
        }
    }

    // MARK: - API

    func connect() async {
        do {
            let i = try await send(try request("v1/hello"), as: HostInfo.self)
            info = i
            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            info = nil
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        isConnected = false
        info = nil
    }

    func listDirectory(_ path: String, permissions: AgentPermissions) async throws -> [String] {
        guard permissions.allowComputerControl else { throw CompanionError.notAuthorized }
        struct Resp: Codable { let entries: [String] }
        let req = try request("v1/fs/list", method: "POST", body: ["path": path])
        return try await send(req, as: Resp.self).entries
    }

    func readFile(_ path: String, permissions: AgentPermissions) async throws -> String {
        guard permissions.allowComputerControl else { throw CompanionError.notAuthorized }
        struct Resp: Codable { let content: String }
        let req = try request("v1/fs/read", method: "POST", body: ["path": path])
        return try await send(req, as: Resp.self).content
    }

    func writeFile(_ path: String, content: String, permissions: AgentPermissions) async throws {
        guard permissions.allowComputerControl else { throw CompanionError.notAuthorized }
        struct Resp: Codable { let ok: Bool }
        let req = try request("v1/fs/write", method: "POST", body: ["path": path, "content": content])
        _ = try await send(req, as: Resp.self)
    }

    /// Runs a command; the companion asks the desktop user for approval unless it is allow-listed.
    func run(command: String, cwd: String?, permissions: AgentPermissions) async throws -> CommandResult {
        guard permissions.allowComputerControl else { throw CompanionError.notAuthorized }
        var body: [String: Any] = ["command": command]
        if let cwd { body["cwd"] = cwd }
        let req = try request("v1/exec", method: "POST", body: body)
        return try await send(req, as: CommandResult.self)
    }

    func pair(pairingCode: String, hostAddress: String) async throws {
        host = hostAddress
        struct Resp: Codable { let key: String }
        guard let baseURL else { throw CompanionError.notConfigured }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/pair"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": pairingCode, "device": "iPhone"])
        let resp = try await send(req, as: Resp.self)
        KeychainStore.set(resp.key, for: .companionKey)
        await connect()
    }
}

/// Small property wrapper so services can use UserDefaults without SwiftUI.
@propertyWrapper
struct AppStorageBacked<Value> {
    let key: String
    let defaultValue: Value

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value {
        get { UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
