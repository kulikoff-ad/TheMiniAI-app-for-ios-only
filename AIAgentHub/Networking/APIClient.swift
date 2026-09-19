import Foundation
/// Thin wrapper for authorized URLRequests — centralized User-Agent and error handling.
enum APIClient {
    static let userAgent = "AIAgentHub/1.1 (iOS)"
    static func authorizedRequest(url: URL, token: String?) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let t = token, !t.isEmpty { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return r
    }
}
