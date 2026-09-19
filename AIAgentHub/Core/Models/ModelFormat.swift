import Foundation

/// Model container formats the app knows about.
enum ModelFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case gguf
    case safetensors
    case onnx
    case coreml
    case mlx
    case tflite
    case pytorch
    case tokenizer
    case config
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gguf: return "GGUF"
        case .safetensors: return "SafeTensors"
        case .onnx: return "ONNX"
        case .coreml: return "Core ML"
        case .mlx: return "MLX"
        case .tflite: return "TFLite"
        case .pytorch: return "PyTorch"
        case .tokenizer: return "Tokenizer"
        case .config: return "Config"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .gguf: return "cube.transparent"
        case .safetensors: return "shield.lefthalf.filled"
        case .onnx: return "square.stack.3d.up"
        case .coreml: return "apple.logo"
        case .mlx: return "bolt.square"
        case .tflite: return "square.grid.2x2"
        case .pytorch: return "flame"
        case .tokenizer: return "textformat.abc"
        case .config: return "gearshape"
        case .other: return "doc"
        }
    }

    /// Runtime that can execute this format on device (if any).
    var runtime: InferenceRuntime {
        switch self {
        case .gguf: return .llamaCpp
        case .coreml: return .coreML
        case .mlx: return .mlx
        case .onnx: return .onnxRuntime
        case .tflite: return .unsupported
        case .safetensors, .pytorch: return .unsupported
        case .tokenizer, .config, .other: return .none
        }
    }

    static func detect(fileName: String) -> ModelFormat {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".gguf") { return .gguf }
        if lower.hasSuffix(".safetensors") { return .safetensors }
        if lower.hasSuffix(".onnx") || lower.hasSuffix(".onnx_data") { return .onnx }
        if lower.contains(".mlpackage") || lower.contains(".mlmodelc") || lower.hasSuffix(".mlmodel") { return .coreml }
        if lower.hasSuffix(".npz") || lower.contains("/mlx") || lower.hasPrefix("mlx") { return .mlx }
        if lower.hasSuffix(".tflite") { return .tflite }
        if lower.hasSuffix(".bin") || lower.hasSuffix(".pt") || lower.hasSuffix(".pth") || lower.hasSuffix(".ckpt") { return .pytorch }
        if lower.contains("tokenizer") || lower.hasSuffix(".model") || lower.hasSuffix(".vocab") { return .tokenizer }
        if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") || lower.hasSuffix(".txt") || lower.hasSuffix(".md") { return .config }
        return .other
    }
}

/// On-device inference runtimes.
enum InferenceRuntime: String, Codable, CaseIterable, Identifiable, Hashable {
    case llamaCpp
    case coreML
    case mlx
    case onnxRuntime
    case cloud
    case unsupported
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llamaCpp: return "llama.cpp"
        case .coreML: return "Core ML"
        case .mlx: return "MLX"
        case .onnxRuntime: return "ONNX Runtime"
        case .cloud: return "Cloud"
        case .unsupported: return "Unsupported on iOS"
        case .none: return "—"
        }
    }

    var runsOnDevice: Bool {
        switch self {
        case .llamaCpp, .coreML, .onnxRuntime: return true
        case .mlx: return true // MLX Swift requires A17/M-series; validated by DeviceCapabilities
        case .cloud, .unsupported, .none: return false
        }
    }

    var incompatibilityReason: String? {
        switch self {
        case .unsupported:
            return "This format has no iOS-compatible inference runtime bundled with the app. Convert it to GGUF, Core ML or ONNX first."
        case .none:
            return "This file is an auxiliary asset (config/tokenizer) and cannot be executed on its own."
        default:
            return nil
        }
    }
}

enum Quantization: String, Codable, CaseIterable, Identifiable, Hashable {
    case q2K = "Q2_K", q3KS = "Q3_K_S", q3KM = "Q3_K_M", q3KL = "Q3_K_L"
    case q4_0 = "Q4_0", q4KS = "Q4_K_S", q4KM = "Q4_K_M"
    case q5_0 = "Q5_0", q5KS = "Q5_K_S", q5KM = "Q5_K_M"
    case q6K = "Q6_K", q8_0 = "Q8_0"
    case iq2 = "IQ2", iq3 = "IQ3", iq4 = "IQ4"
    case f16 = "F16", bf16 = "BF16", f32 = "F32"
    case int4 = "INT4", int8 = "INT8"

    var id: String { rawValue }

    static func detect(in fileName: String) -> String? {
        let upper = fileName.uppercased()
        // Longest match first so Q4_K_M wins over Q4_0-like prefixes.
        let ordered = Quantization.allCases.sorted { $0.rawValue.count > $1.rawValue.count }
        for q in ordered where upper.contains(q.rawValue) { return q.rawValue }
        return nil
    }

    /// Rough bits-per-weight used to estimate RAM.
    static func bitsPerWeight(_ raw: String?) -> Double {
        guard let r = raw?.uppercased() else { return 16 }
        if r.contains("F32") { return 32 }
        if r.contains("BF16") || r.contains("F16") { return 16 }
        if r.contains("Q8") || r.contains("INT8") { return 8.5 }
        if r.contains("Q6") { return 6.6 }
        if r.contains("Q5") { return 5.5 }
        if r.contains("Q4") || r.contains("INT4") || r.contains("IQ4") { return 4.6 }
        if r.contains("Q3") || r.contains("IQ3") { return 3.5 }
        if r.contains("Q2") || r.contains("IQ2") { return 2.7 }
        return 16
    }
}
