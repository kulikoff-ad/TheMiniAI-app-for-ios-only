import Foundation

enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func bytes(_ v: Int64) -> String {
        guard v > 0 else { return "—" }
        return byteFormatter.string(fromByteCount: v)
    }

    static func compactCount(_ v: Int?) -> String {
        guard let v else { return "—" }
        let d = Double(v)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fk", d / 1_000) }
        return "\(v)"
    }

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

extension Int64 {
    var gb: Double { Double(self) / 1_073_741_824 }
}
