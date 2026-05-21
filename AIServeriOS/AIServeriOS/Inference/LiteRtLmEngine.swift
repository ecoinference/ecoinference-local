import Foundation

// MARK: - Errors

enum InferenceError: LocalizedError {
    case engineCreationFailed(String)
    case sessionCreationFailed
    case generationFailed(String)
    case noModelLoaded
    case cancelled
    case busy

    var errorDescription: String? {
        switch self {
        case .engineCreationFailed(let msg): return "LiteRT-LM engine creation failed: \(msg)"
        case .sessionCreationFailed:         return "Failed to create inference session."
        case .generationFailed(let msg):     return "Inference failed: \(msg)"
        case .noModelLoaded:                 return "No model loaded. Call load() first."
        case .cancelled:                     return "Inference cancelled."
        case .busy:                          return "Inference already in progress. Please wait."
        }
    }
}

// MARK: - InferenceMessage

/// A single turn in a conversation passed to the inference engine.
struct InferenceMessage {
    let role:      String
    let text:      String
    let imageData: Data?

    init(role: String, text: String, imageData: Data? = nil) {
        self.role      = role
        self.text      = text
        self.imageData = imageData
    }
}

// ── Callback context ──────────────────────────────────────────────────────────

/// Heap-allocated context object passed through the C userData pointer.
///
/// Both `inputBuffer` (prompt text) and `imageBuffer` (optional image bytes)
/// are kept alive here so the raw pointers passed to the C streaming API remain
/// valid for the lifetime of the async operation.
private final class StreamContext {
    let continuation: AsyncStream<String>.Continuation
    /// Null-terminated UTF-8 bytes of the formatted prompt.
    var inputBuffer: ContiguousArray<UInt8>
    /// Raw image bytes for the most-recent user image (nil = text-only).
    var imageBuffer: ContiguousArray<UInt8>?

    init(continuation: AsyncStream<String>.Continuation,
         inputBuffer:  ContiguousArray<UInt8>,
         imageBuffer:  ContiguousArray<UInt8>? = nil) {
        self.continuation = continuation
        self.inputBuffer  = inputBuffer
        self.imageBuffer  = imageBuffer
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
        ctx.continuation.finish()  // finish; caller sees empty stream
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
    private(set) var isMultimodal = false
    private var currentSession: OpaquePointer? // LiteRtLmSession*
    private let sessionLock = NSLock()
    /// True while a session is active — the engine only supports one at a time.
    private var sessionActive = false

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
        maxNumTokens: Int  = 8192,
        multimodal:   Bool = false
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
        // Vision backend must be explicitly set for multimodal models.
        // Passing nil leaves the engine without a vision backend; any image
        // input will cause a native crash — same issue as Android visionBackend.
        let visionBackendStr: String? = multimodal ? "cpu" : nil
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!.path

        let engineSettings = litert_lm_engine_settings_create(
            modelPath, backendStr, visionBackendStr, nil
        )!
        defer { litert_lm_engine_settings_delete(engineSettings) }

        litert_lm_engine_settings_set_max_num_tokens(engineSettings, Int32(maxNumTokens))
        litert_lm_engine_settings_set_cache_dir(engineSettings, cacheDir)
        litert_lm_set_min_log_level(2) // INFO

        guard let newEngine = litert_lm_engine_create(engineSettings) else {
            throw InferenceError.engineCreationFailed("litert_lm_engine_create returned nil")
        }

        engine        = newEngine
        loadedModelId = modelId
        isMultimodal  = multimodal
    }

    // ── Unload ────────────────────────────────────────────────────────────────

    func unload() {
        cancelActiveSession()
        if let e = engine {
            litert_lm_engine_delete(e)
        }
        engine        = nil
        loadedModelId = nil
        isMultimodal  = false
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
    ///
    /// If the engine is multimodal and the most-recent user message contains
    /// image data, the image is passed as a separate kLiteRtLmInputDataTypeImage
    /// input preceding the text prompt (matching the Android input ordering).
    func chatStream(
        messages:    [InferenceMessage],
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

                // Reject concurrent requests — engine supports one session at a time.
                self.sessionLock.lock()
                guard !self.sessionActive else {
                    self.sessionLock.unlock()
                    continuation.finish(throwing: InferenceError.busy)
                    return
                }
                self.sessionActive = true
                self.sessionLock.unlock()

                // Build the full Gemma chat template manually so that:
                //  1. The entire conversation history is included (multi-turn).
                //  2. We have full control over the prompt — no dependency on the
                //     SDK's template heuristics.
                // apply_prompt_template is set to false below so the SDK treats
                // the input as a pre-formatted prompt.
                let prompt = LiteRtLmEngine.buildGemmaPrompt(messages: messages)

                // Null-terminated UTF-8 bytes kept alive via ctx.inputBuffer.
                let promptBytes = ContiguousArray(
                    (prompt.utf8CString).map { UInt8(bitPattern: $0) }
                )

                // Image bytes from the most-recent user message, if any.
                // Only extracted when the engine was loaded with multimodal=true;
                // passing an image to a text-only engine would cause a crash.
                let imageBytes: ContiguousArray<UInt8>? = self.isMultimodal
                    ? messages.last(where: { $0.role == "user" && $0.imageData != nil })
                              .flatMap { ContiguousArray($0.imageData!) }
                    : nil

                // Create session config
                let cfg = litert_lm_session_config_create()!
                litert_lm_session_config_set_max_output_tokens(cfg, Int32(maxTokens))
                litert_lm_session_config_set_apply_prompt_template(cfg, false)
                // Do not set sampler params — let the SDK use its built-in default.
                // TopK(1), TopP(2), and Greedy(3) all return "not implemented yet"
                // in the 0.10.2 iOS dylibs; Unspecified(0) uses the model default.

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
                    self.sessionActive  = false
                    self.sessionLock.unlock()
                    litert_lm_session_delete(session)
                }

                // Bridge AsyncThrowingStream → C callback via an AsyncStream intermediary.
                // ctx retains both inputBuffer and imageBuffer so their backing memory
                // stays alive for the duration of the asynchronous C callback.
                let innerStream = AsyncStream<String> { innerCont in
                    let ctx = StreamContext(
                        continuation: innerCont,
                        inputBuffer:  promptBytes,
                        imageBuffer:  imageBytes
                    )
                    let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                    ctx.inputBuffer.withUnsafeBufferPointer { textBuf in
                        let textInput = LiteRtLmInputData(
                            type: kLiteRtLmInputDataTypeText,
                            data: UnsafeRawPointer(textBuf.baseAddress),
                            size: textBuf.count > 0 ? textBuf.count - 1 : 0  // exclude null terminator
                        )
                        if let imgBuf = ctx.imageBuffer {
                            // Multimodal: pass image first, then text (mirrors Android ordering).
                            imgBuf.withUnsafeBufferPointer { iBuf in
                                var inputs = [
                                    LiteRtLmInputData(
                                        type: kLiteRtLmInputDataTypeImage,
                                        data: UnsafeRawPointer(iBuf.baseAddress),
                                        size: iBuf.count
                                    ),
                                    textInput
                                ]
                                _ = litert_lm_session_generate_content_stream(
                                    session, &inputs, 2, liteRtLmStreamCallback, ctxPtr
                                )
                            }
                        } else {
                            var input = textInput
                            _ = litert_lm_session_generate_content_stream(
                                session, &input, 1, liteRtLmStreamCallback, ctxPtr
                            )
                        }
                    }
                }

                for await token in innerStream {
                    let cleaned = token.removingGemmaStopTokens()
                    if !cleaned.isEmpty { continuation.yield(cleaned) }
                }
                continuation.finish()
            }
        }
    }

    /// Blocking (non-streaming) inference. Returns complete response string.
    func chat(
        messages:    [InferenceMessage],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) throws -> String {
        guard let eng = engine else { throw InferenceError.noModelLoaded }

        sessionLock.lock()
        guard !sessionActive else {
            sessionLock.unlock()
            throw InferenceError.busy
        }
        sessionActive = true
        sessionLock.unlock()
        defer {
            sessionLock.lock()
            sessionActive = false
            sessionLock.unlock()
        }

        let prompt = LiteRtLmEngine.buildGemmaPrompt(messages: messages)

        let cfg = litert_lm_session_config_create()!
        litert_lm_session_config_set_max_output_tokens(cfg, Int32(maxTokens))
        litert_lm_session_config_set_apply_prompt_template(cfg, false)
        // Do not set sampler params — SDK default used (see chatStream comment).

        guard let session = litert_lm_engine_create_session(eng, cfg) else {
            litert_lm_session_config_delete(cfg)
            throw InferenceError.sessionCreationFailed
        }
        litert_lm_session_config_delete(cfg)
        defer { litert_lm_session_delete(session) }

        // Image from the most-recent user message (nil for text-only or text-engine).
        let lastImageData: Data? = isMultimodal
            ? messages.last(where: { $0.role == "user" && $0.imageData != nil })?.imageData
            : nil

        let responses: OpaquePointer?
        if let imgData = lastImageData {
            // Multimodal: pass image first, then formatted text prompt.
            responses = prompt.withCString { cStr in
                imgData.withUnsafeBytes { imgBuf in
                    var inputs = [
                        LiteRtLmInputData(
                            type: kLiteRtLmInputDataTypeImage,
                            data: imgBuf.baseAddress,
                            size: imgBuf.count
                        ),
                        LiteRtLmInputData(
                            type: kLiteRtLmInputDataTypeText,
                            data: UnsafeRawPointer(cStr),
                            size: strlen(cStr)
                        )
                    ]
                    return litert_lm_session_generate_content(session, &inputs, 2)
                }
            }
        } else {
            responses = prompt.withCString { cStr in
                var input = LiteRtLmInputData(
                    type: kLiteRtLmInputDataTypeText,
                    data: UnsafeRawPointer(cStr),
                    size: strlen(cStr)
                )
                return litert_lm_session_generate_content(session, &input, 1)
            }
        }

        guard let responses else {
            throw InferenceError.generationFailed("generate_content returned nil")
        }
        defer { litert_lm_responses_delete(responses) }

        let text = litert_lm_responses_get_response_text_at(responses, 0)
            .map { String(cString: $0) } ?? ""
        return text.removingGemmaStopTokens()
    }

    // ── Gemma prompt formatting ───────────────────────────────────────────────

    /// Formats a list of `InferenceMessage`s into the Gemma chat template.
    ///
    ///   <start_of_turn>user
    ///   {system (if any)}\n\n{message}<end_of_turn>
    ///   <start_of_turn>model
    ///   {reply}<end_of_turn>
    ///   ...
    ///   <start_of_turn>model\n          ← triggers generation
    ///
    /// Image data is passed separately via `LiteRtLmInputData`; the text here
    /// contains only the textual portions of each turn.
    static func buildGemmaPrompt(messages: [InferenceMessage]) -> String {
        var sb = ""

        let systemText = messages
            .filter { $0.role == "system" }
            .map    { $0.text }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var systemInjected = false

        for msg in messages where msg.role != "system" {
            switch msg.role {
            case "user":
                sb += "<start_of_turn>user\n"
                if !systemText.isEmpty && !systemInjected {
                    sb += systemText + "\n\n"
                    systemInjected = true
                }
                sb += msg.text + "<end_of_turn>\n"
            case "assistant":
                sb += "<start_of_turn>model\n"
                sb += msg.text + "<end_of_turn>\n"
            default:
                break
            }
        }

        sb += "<start_of_turn>model\n"
        return sb
    }
}

// MARK: - Stop-token stripping

private extension String {
    /// Removes Gemma special stop tokens that the SDK may include in raw output.
    /// These tokens should never be shown to the end user.
    func removingGemmaStopTokens() -> String {
        var s = self
        // Control tokens emitted by Gemma's tokenizer
        for token in ["<end_of_turn>", "<start_of_turn>", "<eos>", "</s>"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        return s
    }
}
