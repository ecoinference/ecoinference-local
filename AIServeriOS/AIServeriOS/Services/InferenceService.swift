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

    var isMultimodal: Bool {
        lock.lock(); defer { lock.unlock() }
        return engine.isMultimodal
    }

    // ── Load ──────────────────────────────────────────────────────────────────

    /// Loads a .litertlm model. Blocking — may take 5–30 s for large models.
    ///
    /// - Parameter maxNumTokens: KV-cache budget (input + history + output).
    ///   Default 8192 uses the full context window of the Gemma 4 E2B export.
    /// - Parameter multimodal: When true the vision backend is enabled so image
    ///   inputs can be passed. Must match the model's capabilities; enabling it
    ///   for a text-only model adds overhead; omitting it for a vision model
    ///   causes a native crash when an image is provided.
    func load(
        modelId:      String,
        modelPath:    String,
        useGpu:       Bool,
        maxNumTokens: Int  = 8192,
        multimodal:   Bool = false
    ) throws {
        lock.lock(); defer { lock.unlock() }
        try engine.load(modelId: modelId, modelPath: modelPath,
                        useGpu: useGpu, maxNumTokens: maxNumTokens,
                        multimodal: multimodal)
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
        messages:    [InferenceMessage],
        maxTokens:   Int   = 2048,
        temperature: Float = 0.8
    ) -> AsyncThrowingStream<String, Error> {
        engine.chatStream(messages: messages, maxTokens: maxTokens,
                          temperature: temperature)
    }

    func chat(
        messages:    [InferenceMessage],
        maxTokens:   Int   = 2048,
        temperature: Float = 0.8
    ) throws -> String {
        try engine.chat(messages: messages, maxTokens: maxTokens,
                        temperature: temperature)
    }
}
