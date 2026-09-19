import Foundation

/// Sandbox-safe file operations inside Documents/Workspace.
/// Never touches paths outside the app container — iOS sandbox rules are respected.
struct FileTool {

    enum FileToolError: LocalizedError {
        case outsideWorkspace
        case notFound(String)
        case notPermitted(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .outsideWorkspace: return "Path escapes the app workspace. iOS sandbox forbids this."
            case .notFound(let p): return "No such file: \(p)"
            case .notPermitted(let what): return "The agent does not have permission to \(what)."
            case .unreadable(let p): return "Cannot read \(p) as text."
            }
        }
    }

    var permissions: AgentPermissions
    var root: URL = ModelStorage.workspaceRoot

    private func resolve(_ relative: String) throws -> URL {
        let cleaned = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let url = root.appendingPathComponent(cleaned).standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw FileToolError.outsideWorkspace }
        return url
    }

    // MARK: - Operations

    func list(_ path: String = "") throws -> [String] {
        let dir = try resolve(path)
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
        return items.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = ModelStorage.size(of: url)
            return isDir ? "\(url.lastPathComponent)/" : "\(url.lastPathComponent) (\(Fmt.bytes(size)))"
        }.sorted()
    }

    func read(_ path: String, maxBytes: Int = 200_000) throws -> String {
        let url = try resolve(path)
        guard ModelStorage.exists(url) else { throw FileToolError.notFound(path) }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data.prefix(maxBytes), encoding: .utf8) else { throw FileToolError.unreadable(path) }
        return text
    }

    @discardableResult
    func write(_ path: String, contents: String) throws -> URL {
        guard permissions.allowFileWrite else { throw FileToolError.notPermitted("write files") }
        let url = try resolve(path)
        try ModelStorage.ensureParent(url)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func append(_ path: String, contents: String) throws -> URL {
        let existing = (try? read(path)) ?? ""
        return try write(path, contents: existing + contents)
    }

    /// Simple search & replace edit.
    @discardableResult
    func edit(_ path: String, find: String, replace: String) throws -> URL {
        let text = try read(path)
        guard text.contains(find) else { throw FileToolError.notFound("pattern \"\(find)\" in \(path)") }
        return try write(path, contents: text.replacingOccurrences(of: find, with: replace))
    }

    func makeFolder(_ path: String) throws {
        guard permissions.allowFileWrite else { throw FileToolError.notPermitted("create folders") }
        try FileManager.default.createDirectory(at: try resolve(path), withIntermediateDirectories: true)
    }

    func delete(_ path: String) throws {
        guard permissions.allowFileDelete else { throw FileToolError.notPermitted("delete files") }
        try FileManager.default.removeItem(at: try resolve(path))
    }

    /// Zip a folder or file using the system coordinator (no third-party deps).
    func zip(_ path: String, to destination: String) throws -> URL {
        guard permissions.allowFileWrite else { throw FileToolError.notPermitted("create archives") }
        let source = try resolve(path)
        guard ModelStorage.exists(source) else { throw FileToolError.notFound(path) }
        let dest = try resolve(destination.hasSuffix(".zip") ? destination : destination + ".zip")
        try ModelStorage.ensureParent(dest)
        if ModelStorage.exists(dest) { try FileManager.default.removeItem(at: dest) }

        var coordinatorError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.forUploading], error: &coordinatorError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: dest) } catch { thrown = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let thrown { throw thrown }
        return dest
    }

    /// Light-weight document analysis: stats + first lines, usable as LLM context.
    func analyze(_ path: String) throws -> String {
        let url = try resolve(path)
        let size = ModelStorage.size(of: url)
        let text = (try? read(path, maxBytes: 400_000)) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        let preview = lines.prefix(40).joined(separator: "\n")
        return """
        File: \(path)
        Size: \(Fmt.bytes(size))
        Type: \(url.pathExtension.isEmpty ? "unknown" : url.pathExtension)
        Lines: \(lines.count)  Words: \(words)  Characters: \(text.count)

        Preview:
        \(preview)
        """
    }

    func tree(_ path: String = "", depth: Int = 3) -> String {
        guard let root = try? resolve(path) else { return "" }
        var out: [String] = []
        func walk(_ url: URL, _ level: Int, _ indent: String) {
            guard level <= depth else { return }
            let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                out.append("\(indent)\(isDir ? "📁" : "📄") \(item.lastPathComponent)")
                if isDir { walk(item, level + 1, indent + "  ") }
            }
        }
        walk(root, 1, "")
        return out.isEmpty ? "(empty workspace)" : out.joined(separator: "\n")
    }
}
