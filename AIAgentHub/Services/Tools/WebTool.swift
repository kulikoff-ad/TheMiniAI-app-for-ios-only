import Foundation

/// Web search + page fetching/analysis using public endpoints (no API key required).
struct WebTool {

    struct SearchResult: Identifiable, Hashable {
        var id: String { url }
        let title: String
        let url: String
        let snippet: String
    }

    var allowNetwork: Bool = true
    private let session = URLSession(configuration: .default)

    enum WebToolError: LocalizedError {
        case offline
        case badURL(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .offline: return "This agent runs in Offline Mode; web access is disabled."
            case .badURL(let s): return "Not a valid URL: \(s)"
            case .http(let c): return "The site returned HTTP \(c)."
            }
        }
    }

    /// DuckDuckGo HTML endpoint — keyless and works from a mobile client.
    func search(_ query: String, limit: Int = 8) async throws -> [SearchResult] {
        guard allowNetwork else { throw WebToolError.offline }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            throw WebToolError.badURL(query)
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw WebToolError.http(code)
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return Self.parseDuckDuckGo(html: html, limit: limit)
    }

    static func parseDuckDuckGo(html: String, limit: Int) -> [SearchResult] {
        var results: [SearchResult] = []
        let blocks = html.components(separatedBy: "result__body")
        for block in blocks.dropFirst() {
            guard let href = firstMatch(in: block, pattern: "result__a\"[^>]*href=\"([^\"]+)\"")
                    ?? firstMatch(in: block, pattern: "href=\"(https?://[^\"]+)\"") else { continue }
            let title = stripTags(firstMatch(in: block, pattern: "result__a\"[^>]*>(.*?)</a>") ?? "")
            let snippet = stripTags(firstMatch(in: block, pattern: "result__snippet\"[^>]*>(.*?)</a>")
                                    ?? firstMatch(in: block, pattern: "result__snippet[^>]*>(.*?)</") ?? "")
            let cleanURL = decodeDDGRedirect(href)
            guard !title.isEmpty, cleanURL.hasPrefix("http") else { continue }
            results.append(.init(title: title, url: cleanURL, snippet: snippet))
            if results.count >= limit { break }
        }
        return results
    }

    private static func decodeDDGRedirect(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("//") { s = "https:" + s }
        guard s.contains("duckduckgo.com/l/"),
              let comps = URLComponents(string: s),
              let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value else { return s }
        return uddg
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetch a page and return readable text.
    func openPage(_ urlString: String, maxCharacters: Int = 12_000) async throws -> String {
        guard allowNetwork else { throw WebToolError.offline }
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            throw WebToolError.badURL(urlString)
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw WebToolError.http(code)
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return String(Self.readableText(from: html).prefix(maxCharacters))
    }

    static func readableText(from html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg", "nav", "footer"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>.*?</\(tag)>", with: " ",
                                       options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<br[^>]*>|</p>|</div>|</li>|</h[1-6]>", with: "\n",
                                   options: [.regularExpression, .caseInsensitive])
        s = stripTags(s)
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Summarise structure of a site — title, headings, links.
    func analyzeSite(_ urlString: String) async throws -> String {
        guard allowNetwork else { throw WebToolError.offline }
        guard let url = URL(string: urlString) else { throw WebToolError.badURL(urlString) }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        let html = String(data: data, encoding: .utf8) ?? ""
        let title = Self.firstMatch(in: html, pattern: "<title[^>]*>(.*?)</title>").map(Self.stripTags) ?? "(no title)"
        let description = Self.firstMatch(in: html, pattern: "name=\"description\" content=\"([^\"]*)\"") ?? ""
        var headings: [String] = []
        if let re = try? NSRegularExpression(pattern: "<h[12][^>]*>(.*?)</h[12]>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let range = NSRange(html.startIndex..., in: html)
            for m in re.matches(in: html, range: range).prefix(15) {
                if let r = Range(m.range(at: 1), in: html) {
                    let h = Self.stripTags(String(html[r]))
                    if !h.isEmpty { headings.append("• \(h)") }
                }
            }
        }
        let text = Self.readableText(from: html)
        return """
        URL: \(urlString)
        Title: \(title)
        Description: \(description)
        Words: \(text.split(separator: " ").count)

        Headings:
        \(headings.isEmpty ? "(none found)" : headings.joined(separator: "\n"))
        """
    }
}
