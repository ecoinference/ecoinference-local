import Foundation

// MARK: - Errors

enum InferenceError: LocalizedError {
    case engineCreationFailed(String)
    case sessionCreationFailed
    case generationFailed(String)
    case noModelLoaded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .engineCreationFailed(let msg): return "LiteRT-LM engine creation failed: \(msg)"
        case .sessionCreationFailed:         return "Failed to create inference session."
        case .generationFailed(let msg):     return "Inference failed: \(msg)"
        case .noModelLoaded:                 return "No model loaded. Call load() first."
        case .cancelled:                     return "Inference cancelled."
        }
    }
}

// ── Callback context ──────────────────────────────────────────────────────────

/// Heap-allocated context object passed through the C userData pointer.
private final class StreamContext {
    let continuation: AsyncStream<String>.Continuation
    /// Keeps the raw prompt bytes alive for the duration of the C callback.
    var inputBuffer: ContiguousArray<UInt8>

    init(continuation: AsyncStream<String>.Continuation,
         inputBuffer: ContiguousArray<UInt8>) {
        self.continuation  = continuation
        self.inputBuffer   = inputBuffer
    }
}

/// Global C-compatible stream callback — no Swift captures allowed.
/// Context is passed via the userData pointer (Unmanaged retained reference).
private func liteRtLmStreamCallback(
    userData:  UnsafeMutableRawPointer?,
    chunk:     UnsafePointer<CChar>?,
    isFinal:   Bool,
    errorMsg:  UnsafePointer<CChar>?
) {
    guard let userData else { return }
    let ctx = Unmanaged<StreamContext>.fromOpaque(userData).takeUnretainedValue()

    if let errorMsg, errorMsg.pointee != 0 {
        let errStr = String(cString: errorMsg)
        ctx.continuation.finish(throwing: nil)  // finish; caller sees empty stream
        _ = errStr                              // suppress unused warning (error logged)
        if isFinal { Unmanaged<StreamContext>.fromOpaque(userData).release() }
        return
    }

    if let chunk, chunk.pointee != 0 {
        let text = String(cString: chunk)
        if !text.isEmpty { ctx.continuation.yield(text) }
    }

    if isFinal {
        ctx.continuation.finish()
        Unmanaged<StreamContext>.fromOpaque(userData).release()
    }
}

// ── Engine wrapper ────────────────────────────────────────────────────────────

/// Swift wrapper around the LiteRT-LM C engine.
///
/// Thread safety: load()/unload() must be called from a single owner.
/// chatStream() may be called concurrently; each call creates a short-lived
/// session that is destroyed before returning.
final class LiteRtLmEngine {

    private var engine: OpaquePointer? // LiteRtLmEngine*
    private(set) var loadedModelId: String?
    private var currentSession: OpaquePointer? // LiteRtLmSession*
    private let sessionLock = NSLock()

    var isLoaded: Bool { engine != nil }

    // ── Load ──────────────────────────────────────────────────────────────────

    /// Load a .litertlm model file. Blocking — call from a background task.
    ///
    /// - Parameter maxNumTokens: Total KV-cache budget (prompt + history + output
    ///   combined). The model binary is the hard ceiling; the engine silently clamps
    ///   to its compiled limit. Default 8192 uses the full context window of the
    ///   Gemma 4 E2B .litertlm export.
    func load(
        modelId:      String,
        modelPath:    String,
        useGpu:       Bool,
        maxNumTokens: Int = 8192
    ) throws {
        unload()

        // Verify file exists and is plausibly complete
        let attrs = try FileManager.default.attributesOfItem(atPath: modelPath)
        let size = (attrs[.size] as? Int) ?? 0
        guard size > 1_048_576 else {
            throw InferenceError.engineCreationFailed(
                "Model file too small (\(size) bytes). Partial download?"
            )
        }

        let backendStr = useGpu ? "gpu" : "cpu"
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!.path

        let engineSettings = litert_lm_engine_settings_create(
            modelPath, backendStr, nil, nil
        )!
        defer { litert_lm_engine_settings_delete(engineSettings) }

        litert_lm_engine_settings_set_max_num_tokens(engineSettings, Int32(maxNumTokens))
        litert_lm_engine_settings_set_cache_dir(engineSettings, cacheDir)
        litert_lm_set_min_log_level(2) // INFO

        guard let newEngine = litert_lm_engine_create(engineSettings) else {
            throw InferenceError.engineCreationFailed("litert_lm_engine_create returned nil")
        }

        engine = newEngine
        loadedModelId = modelId
    }

    // ── Unload ────────────────────────────────────────────────────────────────

    func unload() {
        cancelActiveSession()
        if let e = engine {
            litert_lm_engine_delete(e)
        }
        engine = nil
        loadedModelId = nil
    }

    deinit { unload() }

    // ── Cancel ────────────────────────────────────────────────────────────────

    func cancelActiveSession() {
        sessionLock.lock()
        let s = currentSession
        sessionLock.unlock()
        if let s { litert_lm_session_cancel_process(s) }
    }

    // ── Streaming inference ───────────────────────────────────────────────────

    /// Streams token chunks for a list of chat messages.
    /// Runs litert_lm_session_generate_content_stream on a detached task.
    func chatStream(
        messages:    [[String: String]],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let eng = engine else {
                continuation.finish(throwing: InferenceError.noModelLoaded)
                return
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }

                // Build Gemma chat prompt
                let prompt = Self.buildGemmaPrompt(messages: messages)

                // Null-terminated UTF-8 bytes kept alive via ctx
                var promptBytes = ContiguousArray(
                    (prompt.utf8CString).map { UInt8(bitPattern: $0) }
                )

                // Create session config
                let cfg = litert_lm_session_config_create()!
                litert_lm_session_config_set_max_output_tokens(cfg, Int32(maxTokens))
                litert_lm_session_config_set_apply_prompt_template(cfg, false)
                var sampler = LiteRtLmSamplerParams(
                    type:        kLiteRtLmSamplerTypeTopK,
                    top_k:       40,
                    top_p:       0.95,
                    temperature: temperature,
                    seed:        0
                )
                litert_lm_session_config_set_sampler_params(cfg, &sampler)

                guard let session = litert_lm_engine_create_session(eng, cfg) else {
                    litert_lm_session_config_delete(cfg)
                    continuation.finish(throwing: InferenceError.sessionCreationFailed)
                    return
                }
                litert_lm_session_config_delete(cfg)

                // Register active session for cancellation support
                self.sessionLock.lock()
                self.currentSession = session
                self.sessionLock.unlock()
                defer {
                    self.sessionLock.lock()
                    self.currentSession = nil
                    self.sessionLock.unlock()
                    litert_lm_session_delete(session)
                }

                // Bridge AsyncThrowingStream → C callback via an AsyncStream intermediary
                let innerStream = AsyncStream<String> { innerCont in
                    // Create context — retained until final callback fires.
                    // The C library calls the callback on its own thread after
                    // generate_content_stream returns, so the input buffer must
                    // stay alive for the entire operation.  ctx owns the buffer
                    // via ctx.inputBuffer; we call withUnsafeBufferPointer on
                    // that copy so the pointer lifetime is tied to the retained ctx.
                    let ctx = StreamContext(continuation: innerCont, inputBuffer: promptBytes)
                    let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                    ctx.inputBuffer.withUnsafeBufferPointer { buf in
                        var input = LiteRtLmInputData(
                            type: kLiteRtLmInputDataTypeText,
                            data: UnsafeRawPointer(buf.baseAddress),
                            size: buf.count > 0 ? buf.count - 1 : 0  // exclude null terminator
                        )
                        _ = litert_lm_session_generate_content_stream(
                            session, &input, 1, liteRtLmStreamCallback, ctxPtr
                        )
                    }
                }

                for await token in innerStream {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }

    /// Blocking (non-streaming) inference. Returns complete response string.
    func chat(
        messages:    [[String: String]],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) throws -> String {
        guard let eng = engine else { throw InferenceError.noModelLoaded }

        let prompt = Self.buildGemmaPrompt(messages: messages)

        let cfg = litert_lm_session_config_create()!
        litert_lm_session_config_set_max_output_tokens(cfg, Int32(maxTokens))
        litert_lm_session_config_set_apply_prompt_template(cfg, false)
        var sampler = LiteRtLmSamplerParams(
            type: kLiteRtLmSamplerTypeTopK,
            top_k: 40, top_p: 0.95,
            temperature: temperature, seed: 0
        )
        litert_lm_session_config_set_sampler_params(cfg, &sampler)

        guard let session = litert_lm_engine_create_session(eng, cfg) else {
            litert_lm_session_config_delete(cfg)
            throw InferenceError.sessionCreationFailed
        }
        litert_lm_session_config_delete(cfg)
        defer { litert_lm_session_delete(session) }

        let responses: OpaquePointer? = prompt.withCString { cStr in
            var input = LiteRtLmInputData(
                type: kLiteRtLmInputDataTypeText,
                data: UnsafeRawPointer(cStr),
                size: strlen(cStr)
            )
            return litert_lm_session_generate_content(session, &input, 1)
        }

        guard let responses else {
            throw InferenceError.generationFailed("generate_content returned nil")
        }
        defer { litert_lm_responses_delete(responses) }

        let text = litert_lm_responses_get_response_text_at(responses, 0)
            .map { String(cString: $0) } ?? ""
        return text
    }

    // ── Gemma prompt formatting ───────────────────────────────────────────────

    /// Formats OpenAI-style messages into the Gemma chat template.
    ///
    ///   <start_of_turn>user
    ///   {system (if any)}\n\n{message}<end_of_turn>
    ///   <start_of_turn>model
    ///   {reply}<end_of_turn>
    ///   ...
    ///   <start_of_turn>model\n          ← triggers generation
    static func buildGemmaPrompt(messages: [[String: String]]) -> String {
        var sb = ""

        let systemText = messages
            .filter { $0["role"] == "system" }
            .compactMap { $0["content"] }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var systemInjected = false

        for msg in messages where msg["role"] != "system" {
            let role    = msg["role"] ?? "user"
            let content = msg["content"] ?? ""

            switch role {
            case "user":
                sb += "<start_of_turn>user\n"
                if !systemText.isEmpty && !systemInjected {
                    sb += systemText + "\n\n"
                    systemInjected = true
                }
                sb += content + "<end_of_turn>\n"
            case "assistant":
                sb += "<start_of_turn>model\n"
                sb += content + "<end_of_turn>\n"
            default:
                break
            }
        }

        sb += "<start_of_turn>model\n"
        return sb
    }
}
