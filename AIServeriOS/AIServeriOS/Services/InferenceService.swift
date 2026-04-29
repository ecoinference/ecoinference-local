import Foundation

/// Coordinates model loading and inference via LiteRtLmEngine.
/// All mutating methods must be called from a background context;
/// the properties are read on any thread (behind a lock).
final class InferenceService {

    static let shared = InferenceService()
    private init() {}

    private let engine = LiteRtLmEngine()
    private let lock   = NSLock()

    var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return engine.isLoaded
    }

    var loadedModelId: String? {
        lock.lock(); defer { lock.unlock() }
        return engine.loadedModelId
    }

    // ── Load ──────────────────────────────────────────────────────────────────

    /// Loads a .litertlm model. Blocking — may take 5–30 s for large models.
    func load(
        modelId:   String,
        modelPath: String,
        useGpu:    Bool,
        maxTokens: Int = 1024
    ) throws {
        lock.lock(); defer { lock.unlock() }
        try engine.load(modelId: modelId, modelPath: modelPath,
                        useGpu: useGpu, maxTokens: maxTokens)
    }

    func unload() {
        lock.lock(); defer { lock.unlock() }
        engine.unload()
    }

    func cancelInference() {
        engine.cancelActiveSession()
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    func chatStream(
        messages:    [[String: String]],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) -> AsyncThrowingStream<String, Error> {
        engine.chatStream(messages: messages, maxTokens: maxTokens,
                          temperature: temperature)
    }

    func chat(
        messages:    [[String: String]],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) throws -> String {
        try engine.chat(messages: messages, maxTokens: maxTokens,
                        temperature: temperature)
    }
}
