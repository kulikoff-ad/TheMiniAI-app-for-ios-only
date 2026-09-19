import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Hardware/OS checks used to decide whether a model can realistically run on this device.
enum DeviceCapabilities {

    static var physicalMemoryBytes: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }

    /// iOS kills apps well before physical RAM is exhausted. This is a conservative
    /// working-set budget that an app may use for weights.
    static var usableMemoryBudgetBytes: Int64 {
        let total = physicalMemoryBytes
        // ~55% of RAM for devices >= 6GB, ~45% below that.
        let ratio: Double = total.gb >= 6 ? 0.55 : 0.45
        return Int64(Double(total) * ratio)
    }

    static var freeDiskBytes: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let v = values?.volumeAvailableCapacityForImportantUsage { return Int64(v) }
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    static var totalDiskBytes: Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
    }

    static var deviceModelIdentifier: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        let id = mirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        return id
    }

    /// MLX / heavy GPU paths need Apple silicon with 8GB+ ideally.
    static var supportsMLX: Bool { physicalMemoryBytes.gb >= 7.5 }

    // MARK: - Compatibility evaluation

    struct Compatibility {
        var canRun: Bool
        var reason: String?
        var estimatedMemoryBytes: Int64
    }

    static func evaluate(model: LocalModel) -> Compatibility {
        let runtime = model.runtime

        if let reason = runtime.incompatibilityReason {
            return .init(canRun: false, reason: reason, estimatedMemoryBytes: 0)
        }
        if runtime == .mlx && !supportsMLX {
            return .init(canRun: false,
                         reason: "The MLX runtime needs a device with at least 8 GB of unified memory. This device reports \(Fmt.bytes(physicalMemoryBytes)).",
                         estimatedMemoryBytes: model.sizeBytes)
        }

        let estimated = estimatedMemory(for: model)
        let budget = usableMemoryBudgetBytes
        if estimated > budget {
            let reason = "Estimated working set is \(Fmt.bytes(estimated)) but this device can only dedicate about \(Fmt.bytes(budget)) to a model (\(Fmt.bytes(physicalMemoryBytes)) total RAM). Pick a smaller parameter count or a lower quantization such as Q4_K_M."
            return .init(canRun: false, reason: reason, estimatedMemoryBytes: estimated)
        }
        return .init(canRun: true, reason: nil, estimatedMemoryBytes: estimated)
    }

    /// Weights + KV cache + runtime overhead.
    static func estimatedMemory(for model: LocalModel) -> Int64 {
        let weights: Int64
        if let params = model.parameterCount, params > 0 {
            let bpw = Quantization.bitsPerWeight(model.quantization)
            weights = Int64(Double(params) * bpw / 8.0)
        } else {
            weights = model.sizeBytes
        }
        let overhead = Int64(Double(weights) * 0.22) + 180 * 1024 * 1024
        return weights + overhead
    }

    static func evaluateBeforeDownload(sizeBytes: Int64) -> String? {
        if sizeBytes >= freeDiskBytes {
            return "Not enough free space. This download needs \(Fmt.bytes(sizeBytes)) but only \(Fmt.bytes(freeDiskBytes)) is available."
        }
        if sizeBytes.gb >= 2 {
            return "Large download: \(Fmt.bytes(sizeBytes)). Use Wi-Fi and keep the app in the foreground to finish faster."
        }
        return nil
    }
}
