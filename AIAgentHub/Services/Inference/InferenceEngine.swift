import Foundation

struct ChatMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case system, user, assistant, tool }
    var id: UUID = UUID()
    var role: Role
    var content: String
    var timestamp: Date = Date()
}

protocol InferenceEngine {
    var displayName: String { get }
    func load() async throws
    func unload() async
    /// Streams tokens; returns the full text.
    func complete(messages: [ChatMessage], temperature: Double, maxTokens: Int,
                  onToken: @escaping (String) -> Void) async throws -> String
}

enum InferenceError: LocalizedError {
    case incompatible(String)
    case runtimeMissing(String)
    case notLoaded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .incompatible(let reason): return "This model cannot be loaded on this device. \(reason)"
        case .runtimeMissing(let r): return "The \(r) runtime is not linked into this build. Add the corresponding Swift package (see README → Local inference) and rebuild."
        case .notLoaded: return "The model is not loaded yet."
        case .cancelled: return "Generation cancelled."
        }
    }
}

/// Chooses the right engine for a local model and enforces device limits before loading.
enum InferenceEngineFactory {

    static func make(for model: LocalModel) throws -> InferenceEngine {
        let compat = DeviceCapabilities.evaluate(model: model)
        guard compat.canRun else {
            throw InferenceError.incompatible(compat.reason ?? "Unsupported configuration.")
        }
        switch model.runtime {
        case .llamaCpp:
            return LlamaCppEngine(model: model)
        case .coreML:
            return CoreMLEngine(model: model)
        case .onnxRuntime:
            return ONNXEngine(model: model)
        case .mlx:
            return MLXEngine(model: model)
        case .cloud, .unsupported, .none:
            throw InferenceError.incompatible(model.runtime.incompatibilityReason ?? "No runtime available.")
        }
    }
}

// MARK: - Engines
//
// Each engine is a thin adapter around an external Swift package. The adapters are written so
// that adding the package (see README) makes them live without touching call sites: the
// `#if canImport(...)` blocks compile the real implementation when the dependency is present,
// and otherwise the app reports a precise, honest error to the user instead of pretending.

final class LlamaCppEngine: InferenceEngine {
    let model: LocalModel
    var displayName: String { "llama.cpp · \(model.displayName)" }
    private var loaded = false

    init(model: LocalModel) { self.model = model }

    var modelURL: URL {
        ModelStorage.location(repoId: model.repoId, revision: model.revision, file: model.fileName)
    }

    func load() async throws {
        guard ModelStorage.exists(modelURL) else { throw InferenceError.incompatible("The GGUF file is missing from storage.") }
        #if canImport(LlamaFramework)
        try await LlamaBridge.shared.load(path: modelURL.path,
                                          contextLength: 4096,
                                          gpuLayers: 99)
        loaded = true
        #else
        throw InferenceError.runtimeMissing("llama.cpp")
        #endif
    }

    func unload() async {
        #if canImport(LlamaFramework)
        await LlamaBridge.shared.unload()
        #endif
        loaded = false
    }

    func complete(messages: [ChatMessage], temperature: Double, maxTokens: Int,
                  onToken: @escaping (String) -> Void) async throws -> String {
        guard loaded else { throw InferenceError.notLoaded }
        #if canImport(LlamaFramework)
        let prompt = PromptFormatter.chatML(messages)
        return try await LlamaBridge.shared.generate(prompt: prompt,
                                                     temperature: Float(temperature),
                                                     maxTokens: maxTokens,
                                                     onToken: onToken)
        #else
        throw InferenceError.runtimeMissing("llama.cpp")
        #endif
    }
}

final class CoreMLEngine: InferenceEngine {
    let model: LocalModel
    var displayName: String { "Core ML · \(model.displayName)" }
    init(model: LocalModel) { self.model = model }

    func load() async throws {
        let url = ModelStorage.location(repoId: model.repoId, revision: model.revision, file: model.fileName)
        guard ModelStorage.exists(url) else { throw InferenceError.incompatible("The Core ML package is missing from storage.") }
        throw InferenceError.runtimeMissing("Core ML text-generation host (CoreMLTextGen)")
    }
    func unload() async {}
    func complete(messages: [ChatMessage], temperature: Double, maxTokens: Int,
                  onToken: @escaping (String) -> Void) async throws -> String {
        throw InferenceError.runtimeMissing("Core ML text-generation host (CoreMLTextGen)")
    }
}

final class ONNXEngine: InferenceEngine {
    let model: LocalModel
    var displayName: String { "ONNX Runtime · \(model.displayName)" }
    init(model: LocalModel) { self.model = model }
    func load() async throws { throw InferenceError.runtimeMissing("ONNX Runtime GenAI") }
    func unload() async {}
    func complete(messages: [ChatMessage], temperature: Double, maxTokens: Int,
                  onToken: @escaping (String) -> Void) async throws -> String {
        throw InferenceError.runtimeMissing("ONNX Runtime GenAI")
    }
}

final class MLXEngine: InferenceEngine {
    let model: LocalModel
    var displayName: String { "MLX · \(model.displayName)" }
    init(model: LocalModel) { self.model = model }
    func load() async throws {
        guard DeviceCapabilities.supportsMLX else {
            throw InferenceError.incompatible("MLX needs at least 8 GB of unified memory.")
        }
        throw InferenceError.runtimeMissing("MLX Swift")
    }
    func unload() async {}
    func complete(messages: [ChatMessage], temperature: Double, maxTokens: Int,
                  onToken: @escaping (String) -> Void) async throws -> String {
        throw InferenceError.runtimeMissing("MLX Swift")
    }
}

enum PromptFormatter {
    static func chatML(_ messages: [ChatMessage]) -> String {
        var out = ""
        for m in messages {
            out += "<|im_start|>\(m.role.rawValue)\n\(m.content)<|im_end|>\n"
        }
        out += "<|im_start|>assistant\n"
        return out
    }
}

/// Cloud engine used when an agent is bound to a hosted model.
final class CloudEngine: InferenceEngine {
    let provider: CloudProvider
    let modelId: String
    var displayName: String { "\(provider.title) · \(modelId)" }

    init(provider: CloudProvider, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }

    func load() async throws {}
    func unload() async {}

    func complete(messages: [ChatMessage], temperature: Double, maxTokens: Int,
                  onToken: @escaping (String) -> Void) async throws -> String {
        let payload = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        switch provider {
        case .huggingFace:
            let text = try await HuggingFaceAPI.shared.chatCompletion(
                model: modelId, messages: payload, temperature: temperature, maxTokens: maxTokens)
            onToken(text)
            return text
        case .openAICompatible:
            return try await openAICompatible(payload: payload, temperature: temperature, maxTokens: maxTokens, onToken: onToken)
        }
    }

    private func openAICompatible(payload: [[String: String]], temperature: Double, maxTokens: Int,
                                  onToken: @escaping (String) -> Void) async throws -> String {
        let baseString = UserDefaults.standard.string(forKey: "openai.baseURL") ?? "https://api.openai.com/v1"
        guard let url = URL(string: baseString + "/chat/completions"),
              let key = KeychainStore.get(.openAIKey), !key.isEmpty else {
            throw InferenceError.runtimeMissing("OpenAI-compatible endpoint (set base URL and key in Settings)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelId, "messages": payload,
            "temperature": temperature, "max_tokens": maxTokens
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw HFError.http(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw HFError.decoding("chat completion")
        }
        onToken(content)
        return content
    }
}
