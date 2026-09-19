import Foundation

/// Filesystem layout for downloaded models, inside the app sandbox.
/// Application Support/Models/<owner__repo>/<revision>/<file>
enum ModelStorage {

    static var modelsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var mutable = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
        return mutable
    }

    static var workspaceRoot: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var resumeDataRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ResumeData", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func location(repoId: String, revision: String, file: String) -> URL {
        modelsRoot
            .appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
            .appendingPathComponent(file)
    }

    static func ensureParent(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static func size(of url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func delete(_ url: URL) throws {
        guard exists(url) else { return }
        try FileManager.default.removeItem(at: url)
        // Clean up now-empty parents up to modelsRoot.
        var parent = url.deletingLastPathComponent()
        while parent.path.hasPrefix(modelsRoot.path), parent.path != modelsRoot.path {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
            if contents.isEmpty {
                try? FileManager.default.removeItem(at: parent)
                parent = parent.deletingLastPathComponent()
            } else { break }
        }
    }

    static func totalUsedBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(at: modelsRoot, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e { total += size(of: url) }
        return total
    }
}
