import Foundation
import os.log
import Darwin
import UIKit

private let engineLog = Logger(subsystem: "ai.ecoinference.app", category: "LiteRtLmEngine")

// MARK: - Errors

enum InferenceError: LocalizedError {
    case engineCreationFailed(String)
    case outOfMemory(available: Int, resident: Int, required: Int)
    case sessionCreationFailed
    case generationFailed(String)
    case noModelLoaded
    case cancelled
    case busy

    var errorDescription: String? {
        switch self {
        case .engineCreationFailed(let msg):
            return "LiteRT-LM engine creation failed: \(msg)"
        case .outOfMemory(let available, let resident, let required):
            return "Not enough memory to load the model. " +
                   "Available: \(available) MB, in use: \(resident) MB, " +
                   "estimated need: ~\(required) MB. " +
                   "Force-quit other apps and try again."
        case .sessionCreationFailed:
            return "Failed to create inference session."
        case .generationFailed(let msg):
            return "Inference failed: \(msg)"
        case .noModelLoaded:
            return "No model loaded. Call load() first."
        case .cancelled:
            return "Inference cancelled."
        case .busy:
            return "Inference already in progress. Please wait."
        }
    }
}

// MARK: - Memory helpers

/// Bytes available to this process before the OS would jetsam it.
/// Uses os_proc_available_memory() — the same signal the OS uses for memory pressure.
private func processAvailableMemoryMB() -> Int {
    // os_proc_available_memory() is available on iOS 13+ / macOS 10.15+.
    // It returns the number of bytes the process can still allocate before
    // the kernel would kill it for memory pressure.
    let bytes = os_proc_available_memory()
    return Int(bytes) / (1_024 * 1_024)
}

/// Current resident memory of this process in MB.
private func residentMemoryMB() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Int(info.resident_size) / (1_024 * 1_024)
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
/// Retains the AsyncStream continuation and the input buffer so raw C pointers
/// passed to `litert_lm_session_generate_content_stream` remain valid for the
/// entire async operation.
private final class StreamContext {
    let continuation: AsyncStream<String>.Continuation
    var inputBuffer:  ContiguousArray<UInt8>

    init(continuation: AsyncStream<String>.Continuation,
         inputBuffer:  ContiguousArray<UInt8>) {
        self.continuation = continuation
        self.inputBuffer  = inputBuffer
    }
}

// ── Conversation-API callback support ────────────────────────────────────────

/// Heap-allocated context for Conversation-API streaming callbacks.
/// Each callback fires with a JSON chunk:
///   {"role":"assistant","content":[{"type":"text","text":"<token>"}]}
private final class ConvStreamContext {
    let continuation: AsyncStream<String>.Continuation
    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }
}

/// Extracts plain-text from a Conversation-API stream chunk without invoking
/// JSONSerialization on every token (hot path: ~100 calls per response).
///
/// Chunk format: {"role":"assistant","content":[{"type":"text","text":"<val>"}]}
/// We walk backwards through all "text":"..." occurrences; the last one is the
/// content value (the earlier one is inside "type":"text").
private func convChunkText(_ json: String) -> String? {
    var last: Range<String.Index>? = nil
    var search = json.startIndex..<json.endIndex
    while let r = json.range(of: "\"text\":\"", range: search) {
        last    = r
        search  = r.upperBound..<json.endIndex
    }
    guard let r = last else { return nil }
    var result  = ""
    var escaped = false
    for ch in json[r.upperBound...] {
        if escaped {
            switch ch {
            case "n":   result += "\n"
            case "r":   result += "\r"
            case "t":   result += "\t"
            case "\"":  result += "\""
            case "\\":  result += "\\"
            default:    result += String(ch)
            }
            escaped = false
        } else if ch == "\\" {
            escaped = true
        } else if ch == "\"" {
            break
        } else {
            result += String(ch)
        }
    }
    return result
}

/// Global C-compatible callback for litert_lm_conversation_send_message_stream.
/// Parses JSON chunks and forwards plain text to the AsyncStream continuation.
private func liteRtLmConvStreamCallback(
    userData: UnsafeMutableRawPointer?,
    chunk:    UnsafePointer<CChar>?,
    isFinal:  Bool,
    errorMsg: UnsafePointer<CChar>?
) {
    guard let userData else { return }
    let ctx = Unmanaged<ConvStreamContext>.fromOpaque(userData).takeUnretainedValue()

    if let errorMsg, errorMsg.pointee != 0 {
        let msg = String(cString: errorMsg)
        engineLog.error("convStreamCallback: error=\(msg) isFinal=\(isFinal)")
        ctx.continuation.finish()
        if isFinal { Unmanaged<ConvStreamContext>.fromOpaque(userData).release() }
        return
    }

    if let chunk, chunk.pointee != 0 {
        let raw = String(cString: chunk)
        // Each chunk is a JSON object — extract the text value.
        if let text = convChunkText(raw), !text.isEmpty {
            ctx.continuation.yield(text)
        }
    }

    if isFinal {
        engineLog.debug("convStreamCallback: isFinal=true — finishing")
        ctx.continuation.finish()
        Unmanaged<ConvStreamContext>.fromOpaque(userData).release()
    }
}

// ── Session-API callback ──────────────────────────────────────────────────────

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
        ctx.continuation.finish()
        if isFinal { Unmanaged<StreamContext>.fromOpaque(userData).release() }
        return
    }

    if let chunk, chunk.pointee != 0 {
        let text = String(cString: chunk)
        if !text.isEmpty { ctx.continuation.yield(text) }
    }

    if isFinal {
        engineLog.debug("sessionStreamCallback: isFinal=true — finishing continuation")
        ctx.continuation.finish()
        Unmanaged<StreamContext>.fromOpaque(userData).release()
    }
}

// ── Engine wrapper ────────────────────────────────────────────────────────────

/// Swift wrapper around the LiteRT-LM C engine.
///
/// Both multimodal and non-multimodal engines use one `LiteRtLmSession` created
/// at load time and reused for every inference call (the SDK hangs on a second
/// `create_session` call).
///
/// Multimodal inference (Gemma 4 E2B): uses the Conversation API
/// (`litert_lm_conversation_create`).  `litert_lm_conversation_create`
/// internally creates the engine's session, so we must NOT also call
/// `litert_lm_engine_create_session` for multimodal — only one session may
/// exist at a time.  We create the Conversation lazily on the first inference
/// call and keep it alive across calls.
///
/// The `litert_lm_conversation_config_create` function in the v0.12.0 dylib
/// takes 5 optional arguments (confirmed by disassembly); the shipped header
/// incorrectly declared it as (void) which caused a SIGSEGV from garbage
/// register values.  We call it with all-NULL arguments to get an empty config
/// and then configure it with the individual setter functions.
final class LiteRtLmEngine {

    private var engine:                 OpaquePointer? // LiteRtLmEngine*
    private var persistentSession:      OpaquePointer? // LiteRtLmSession* — non-multimodal only
    private var persistentConversation: OpaquePointer? // LiteRtLmConversation* — multimodal only (lazy)
    // Keep configs alive as long as the conversation lives.
    // Hypothesis: the C library holds a pointer into convCfg/sessCfg rather than
    // copying, so deleting them (even after conversation_create) corrupts state
    // and causes send_message to return nil.
    private var persistentConvCfg:  OpaquePointer? // LiteRtLmConversationConfig*
    private var persistentSessCfg:  OpaquePointer? // LiteRtLmSessionConfig*
    private(set) var loadedModelId: String?
    private(set) var isMultimodal = false
    private let sessionLock = NSLock()
    /// True while an inference call is in progress.
    private var sessionActive = false
    /// Number of InferenceMessages already committed to the session's KV cache.
    /// Used to build incremental prompts for non-multimodal sessions.
    private var committedMessageCount: Int = 0
    /// Number of user turns already sent to `persistentConversation`.
    private var committedConvTurnCount: Int = 0
    /// Max JPEG dimension for multimodal image inputs, computed from maxNumTokens at load time.
    /// Each 16×16 patch costs one KV token; an 800 px image generates ~2500 patches which
    /// overflows a 2048-token context after output reservation.
    private var maxVisionDimension: CGFloat = 800
    /// Max output tokens for the conversation session config — smaller for low-context models
    /// to leave more KV budget available for image patches and the prompt prefill.
    private var maxConvOutputTokens: Int32 = 512

    var isLoaded: Bool { engine != nil && (persistentSession != nil || isMultimodal) }

    /// Reset conversation state so the next chat() / chatStream() call starts fresh.
    ///
    /// For non-multimodal: resets `committedMessageCount`; the session KV-cache retains
    /// old tokens but the model receives a clean first-turn prompt on the next call.
    ///
    /// For multimodal: deletes the persistent Conversation object so the next call
    /// creates a fresh one (the Conversation API owns its own KV-cache internally).
    func resetConversation() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        committedMessageCount  = 0
        committedConvTurnCount = 0
        if let conv = persistentConversation {
            litert_lm_conversation_delete(conv)
            persistentConversation = nil
            dlog("resetConversation: persistentConversation deleted")
        }
        if let cfg = persistentConvCfg {
            litert_lm_conversation_config_delete(cfg)
            persistentConvCfg = nil
        }
        if let cfg = persistentSessCfg {
            litert_lm_session_config_delete(cfg)
            persistentSessCfg = nil
        }
        dlog("resetConversation: committedMessageCount=0 committedConvTurnCount=0")
    }

    // ── Load ──────────────────────────────────────────────────────────────────

    /// Load a .litertlm model file. Blocking — call from a background task.
    ///
    /// - Parameter maxNumTokens: Total KV-cache budget (prompt + history + output
    ///   combined). The model binary is the hard ceiling; the engine silently clamps
    ///   to its compiled limit. Default 8192 uses the full context window of the
    ///   Gemma 4 E2B .litertlm export.
    func load(
        modelId:             String,
        modelPath:           String,
        useGpu:              Bool,
        maxNumTokens:        Int  = 8192,
        multimodal:          Bool = false,
        speculativeDecoding: Bool = false
    ) throws {
        unload()

        // Verify file exists and is plausibly complete
        let attrs = try FileManager.default.attributesOfItem(atPath: modelPath)
        let size = (attrs[.size] as? Int) ?? 0
        dlog("load: modelPath=\(modelPath) size=\(size) bytes (\(size / 1_048_576) MB)")
        // Require at least 100 MB — a 1 MB floor would accept a heavily-truncated download
        // that the engine loads without error but fails at inference time.
        guard size > 100 * 1_048_576 else {
            throw InferenceError.engineCreationFailed(
                "Model file too small (\(size / 1_048_576) MB). Partial download?"
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

        engineLog.debug("load: engine_settings_create — backend=\(backendStr) visionBackend=\(visionBackendStr ?? "nil") multimodal=\(multimodal)")
        let engineSettings = litert_lm_engine_settings_create(
            modelPath, backendStr, visionBackendStr, nil
        )!
        defer { litert_lm_engine_settings_delete(engineSettings) }

        engineLog.debug("load: max_num_tokens=\(maxNumTokens) max_num_images=\(multimodal ? 1 : 0) cache_dir set")
        litert_lm_engine_settings_set_max_num_tokens(engineSettings, Int32(maxNumTokens))
        if multimodal {
            litert_lm_engine_settings_set_max_num_images(engineSettings, 1)
        }
        litert_lm_engine_settings_set_cache_dir(engineSettings, cacheDir)
        litert_lm_engine_settings_enable_benchmark(engineSettings)
        if speculativeDecoding {
            litert_lm_engine_settings_set_enable_speculative_decoding(engineSettings, true)
            engineLog.info("load: speculative decoding enabled")
        }
        litert_lm_set_min_log_level(2) // ERROR only (0=INFO 1=WARNING 2=ERROR 3=FATAL)

        // ── Memory snapshot before the long engine-init ──────────────────────
        let availBefore   = processAvailableMemoryMB()
        let residentBefore = residentMemoryMB()
        // Rough lower bound on RAM a multimodal model requires while the engine
        // is initialising all TFLite subgraphs.  Non-multimodal models need ~600 MB.
        let estimatedRequired = multimodal ? 1_500 : 600
        dlog("load: memory before engine_create — available=\(availBefore) MB  resident=\(residentBefore) MB  estimatedRequired=\(estimatedRequired) MB")
        if availBefore < estimatedRequired {
            engineLog.warning("load: available memory (\(availBefore) MB) may be insufficient (need ~\(estimatedRequired) MB)")
        }

        engineLog.info("load: calling litert_lm_engine_create — maxNumTokens=\(maxNumTokens) multimodal=\(multimodal)")
        guard let newEngine = litert_lm_engine_create(engineSettings) else {
            let availAfter    = processAvailableMemoryMB()
            let residentAfter = residentMemoryMB()
            let memConsumed   = residentAfter - residentBefore   // MB consumed during init
            dlog("load: litert_lm_engine_create returned nil — available=\(availAfter) MB  resident=\(residentAfter) MB  consumed≈\(memConsumed) MB")

            // Classify as OOM when available memory is critically low OR the
            // process consumed more than expected, leaving very little headroom.
            let oomLikely = availAfter < 150 || availBefore < estimatedRequired
            if oomLikely {
                engineLog.error("load: classifying as OOM — availAfter=\(availAfter) MB  availBefore=\(availBefore) MB")
                throw InferenceError.outOfMemory(
                    available: availAfter,
                    resident:  residentAfter,
                    required:  estimatedRequired
                )
            }
            throw InferenceError.engineCreationFailed("litert_lm_engine_create returned nil")
        }
        let availAfterOK    = processAvailableMemoryMB()
        let residentAfterOK = residentMemoryMB()
        dlog("load: engine created OK — available=\(availAfterOK) MB  resident=\(residentAfterOK) MB")

        // For non-multimodal engines: create one persistent LiteRtLmSession at load time.
        // The SDK does not support creating a second session, so this session lives
        // for the entire model lifetime. max_output_tokens=2048, prompt template off
        // (we build the Gemma 2 prompt manually via buildGemmaPrompt).
        //
        // For multimodal engines (Gemma 4 E2B): we do NOT create a session here.
        // litert_lm_conversation_create() creates the engine's session internally, and
        // only one session may exist at a time — creating a session here and then a
        // Conversation would violate that constraint. The Conversation is created lazily
        // on the first chatStream / chat call via makeConversation().
        var newSession: OpaquePointer? = nil
        if !multimodal {
            guard let sessCfg = litert_lm_session_config_create() else {
                derr("load: litert_lm_session_config_create returned nil")
                litert_lm_engine_delete(newEngine)
                throw InferenceError.sessionCreationFailed
            }
            litert_lm_session_config_set_max_output_tokens(sessCfg, 2048)
            engineLog.debug("load: creating session — max_output_tokens=2048")
            guard let sess = litert_lm_engine_create_session(newEngine, sessCfg) else {
                derr("load: litert_lm_engine_create_session returned nil")
                litert_lm_session_config_delete(sessCfg)
                litert_lm_engine_delete(newEngine)
                throw InferenceError.sessionCreationFailed
            }
            litert_lm_session_config_delete(sessCfg)
            newSession = sess
            dlog("load: engine + persistent session created for \(modelId)")
        } else {
            dlog("load: multimodal engine created for \(modelId) — Conversation deferred to first call")
        }

        // Derive vision budget from context size.
        // At 16×16 patches, an 800 px image produces ~2500 patch tokens — more than the
        // entire 2048-token context of E4B.  Scale both the image ceiling and the output
        // reservation down so patch tokens + text + output fit inside maxNumTokens.
        //   E4B (2048): 448 px → 28×28 = 784 patches; 256 output → input budget 1792 ✓
        //   E2B (4096): 800 px → 50×50 = 2500 patches; 512 output → input budget 3584 ✓
        maxVisionDimension  = maxNumTokens <= 2048 ? 448 : 800
        maxConvOutputTokens = maxNumTokens <= 2048 ? 256 : 512
        dlog("load: maxVisionDimension=\(Int(maxVisionDimension))px maxConvOutputTokens=\(maxConvOutputTokens)")

        engine                = newEngine
        persistentSession     = newSession
        loadedModelId         = modelId
        isMultimodal          = multimodal
        committedMessageCount = 0
    }

    // ── Unload ────────────────────────────────────────────────────────────────

    func unload() {
        cancelActiveSession()
        if let conv = persistentConversation { litert_lm_conversation_delete(conv) }
        if let cfg  = persistentConvCfg      { litert_lm_conversation_config_delete(cfg) }
        if let cfg  = persistentSessCfg      { litert_lm_session_config_delete(cfg) }
        if let s    = persistentSession      { litert_lm_session_delete(s) }
        if let e    = engine                 { litert_lm_engine_delete(e) }
        persistentConversation = nil
        persistentConvCfg      = nil
        persistentSessCfg      = nil
        persistentSession      = nil
        engine                 = nil
        loadedModelId          = nil
        isMultimodal           = false
        committedMessageCount  = 0
        committedConvTurnCount = 0
        maxVisionDimension     = 800
        maxConvOutputTokens    = 512
        dlog("unload: conversation + session + engine destroyed")
    }

    deinit { unload() }

    // ── Cancel ────────────────────────────────────────────────────────────────

    func cancelActiveSession() {
        // Only Conversation has a cancel API; LiteRtLmSession has none in v0.12.0.
        if let conv = persistentConversation { litert_lm_conversation_cancel_process(conv) }
    }

    // ── Conversation API helpers ──────────────────────────────────────────────

    /// Escapes a Swift string for safe embedding inside a JSON string literal.
    private static func jsonEscape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out += String(scalar)
                }
            }
        }
        return out
    }

    /// Returns JPEG data resized so its longest edge is ≤ `maxDimension` pixels.
    ///
    /// The Gemma 4 E2B vision encoder works with 16×16 patches; max_num_patches=2520
    /// gives a maximum effective resolution of ≈ 800×800 px.  Sending a full-resolution
    /// iPhone photo (4032×3024, ~4 MB JPEG → ~5 MB base64) can exceed internal JSON
    /// string-buffer limits and cause `send_message` to return nil.  We pre-scale the
    /// image so the base64 payload stays well under 1 MB.
    private static func scaledJpegData(_ data: Data,
                                        maxDimension: CGFloat = 800,
                                        quality: CGFloat = 0.85) -> Data {
        guard let image = UIImage(data: data) else {
            engineLog.error("scaledJpegData: UIImage(data:) failed — using original \(data.count) bytes")
            return data
        }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else {
            // Already fits — just re-encode to ensure it's JPEG.
            let out = image.jpegData(compressionQuality: quality) ?? data
            engineLog.debug("scaledJpegData: already ≤\(Int(maxDimension))px — recompressed \(data.count)→\(out.count) bytes")
            return out
        }
        let scale   = maxDimension / longest
        let newSize = CGSize(width: (image.size.width  * scale).rounded(),
                             height: (image.size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        let out      = resized.jpegData(compressionQuality: quality) ?? data
        engineLog.debug("scaledJpegData: \(Int(image.size.width))×\(Int(image.size.height)) → \(Int(newSize.width))×\(Int(newSize.height)) | \(data.count)→\(out.count) bytes")
        return out
    }

    /// Detects whether `data` begins with a JPEG or PNG magic number.
    private static func mimeType(for data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }
        let b0 = data[data.startIndex]
        let b1 = data[data.startIndex + 1]
        if b0 == 0x89 && b1 == 0x50 { return "image/png" }   // PNG: 0x89 'P'
        if b0 == 0xFF && b1 == 0xD8 { return "image/jpeg" }  // JPEG: SOI marker
        return "image/jpeg"                                   // default
    }

    /// Builds the `message_json` argument for `litert_lm_conversation_send_message[_stream]`.
    ///
    /// Format confirmed from flutter_gemma native-v0.12.0 litert_lm_client.dart:
    ///
    ///   Text only:
    ///     {"role":"user","content":[{"type":"text","text":"<escaped>"}]}
    ///
    ///   Image + text:
    ///     {"role":"user","content":[
    ///       {"type":"image","blob":"<base64>"},
    ///       {"type":"text","text":"<escaped>"}
    ///     ]}
    ///
    /// Images are pre-scaled to ≤ 800×800 px before base64 encoding to keep the
    /// JSON payload manageable (raw iPhone photos can exceed internal buffer limits).
    private static func buildConversationMessageJson(text: String, imageData: Data?,
                                                      maxVisionDimension: CGFloat = 800) -> String {
        var items = ""
        if let raw = imageData {
            let jpeg = scaledJpegData(raw, maxDimension: maxVisionDimension)
            let b64  = jpeg.base64EncodedString()
            engineLog.debug("buildConversationMessageJson: image \(raw.count)→\(jpeg.count) bytes b64=\(b64.count) chars")
            items += "{\"type\":\"image\",\"blob\":\"\(b64)\"}"
            items += ","
        }
        items += "{\"type\":\"text\",\"text\":\"\(jsonEscape(text))\"}"
        return "{\"role\":\"user\",\"content\":[\(items)]}"
    }

    /// Creates (or recreates) a `LiteRtLmConversation` for multimodal inference.
    ///
    /// Uses the patched 6-arg `litert_lm_conversation_config_create` in the
    /// native-v0.12.0 dylib (engine is the first required argument).
    ///
    /// max_output_tokens=512 in the session config leaves a 3584-token input budget
    /// (4096-512), which exceeds max_num_patches=2520 so a full image fits.
    private func makeConversation(systemText: String) throws -> OpaquePointer {
        guard let eng = engine else { throw InferenceError.noModelLoaded }

        // Session config: set max_output_tokens and sampler params.
        // The flutter_gemma Dart reference client ALWAYS sets sampler params
        // (type=TopP) before calling conversation_config_create.  Without explicit
        // sampler params the session config defaults to kTypeUnspecified=0, which
        // causes litert_lm_conversation_send_message to return nil silently.
        guard let sessCfg = litert_lm_session_config_create() else {
            throw InferenceError.sessionCreationFailed
        }
        litert_lm_session_config_set_max_output_tokens(sessCfg, maxConvOutputTokens)
        var samplerParams = LiteRtLmSamplerParams(
            type:        kTopP,
            top_k:       40,
            top_p:       0.95,
            temperature: 1.0,
            seed:        0
        )
        litert_lm_session_config_set_sampler_params(sessCfg, &samplerParams)

        // Patched 6-arg config_create — engine MUST be non-nil or returns nil.
        // system_message_json: plain text (not a JSON content item).
        // tools_json / messages_json: nil (no tools, fresh conversation).
        // enable_constrained_decoding: false (only needed with tools).
        //
        // NOTE: sessCfg and cfg are stored in persistentSessCfg/persistentConvCfg
        // rather than deleted immediately.  The C library may hold a pointer into
        // these structs (rather than copying), so deleting them before send_message
        // would leave the conversation with dangling references.
        engineLog.debug("makeConversation: config_create systemText.count=\(systemText.count)")
        let cfg: OpaquePointer? = systemText.isEmpty
            ? litert_lm_conversation_config_create(eng, sessCfg, nil, nil, nil, false)
            : systemText.withCString { sysPtr in
                litert_lm_conversation_config_create(eng, sessCfg, sysPtr, nil, nil, false)
            }
        guard let cfg else {
            litert_lm_session_config_delete(sessCfg)
            engineLog.error("makeConversation: config_create returned nil")
            throw InferenceError.sessionCreationFailed
        }

        guard let conv = litert_lm_conversation_create(eng, cfg) else {
            litert_lm_conversation_config_delete(cfg)
            litert_lm_session_config_delete(sessCfg)
            engineLog.error("makeConversation: conversation_create returned nil")
            throw InferenceError.sessionCreationFailed
        }
        // Store configs alongside the conversation so they remain valid for
        // the entire lifetime of the conversation object.
        persistentConvCfg = cfg
        persistentSessCfg = sessCfg
        dlog("makeConversation: created OK conv=\(conv) — configs retained")
        return conv
    }

    // ── Benchmark logging ─────────────────────────────────────────────────────

    /// Reads the latest benchmark snapshot from a Conversation and logs
    /// TTFT and decode tokens/sec via dlog() (on-device debug log).
    /// Safe to call even if benchmarking is unavailable — returns silently
    /// if get_benchmark_info returns nil.
    private func logBenchmark(conversation: OpaquePointer) {
        guard let info = litert_lm_conversation_get_benchmark_info(conversation) else {
            engineLog.debug("logBenchmark: get_benchmark_info returned nil (benchmark not enabled?)")
            return
        }
        defer { litert_lm_benchmark_info_delete(info) }

        let ttft       = litert_lm_benchmark_info_get_time_to_first_token(info)
        let numDecodes = litert_lm_benchmark_info_get_num_decode_turns(info)

        // Use the last decode turn for tokens/sec (most recent inference).
        var decodeTps   = 0.0
        var decodeCount: Int32 = 0
        if numDecodes > 0 {
            let idx     = Int32(numDecodes - 1)
            decodeTps   = litert_lm_benchmark_info_get_decode_tokens_per_sec_at(info, idx)
            decodeCount = litert_lm_benchmark_info_get_decode_token_count_at(info, idx)
        }

        dlog(String(format: "benchmark: TTFT=%.3fs  decode=%.1f tok/s (%d tokens)",
                    ttft, decodeTps, decodeCount))
    }

    // ── Streaming inference ───────────────────────────────────────────────────

    /// Streams token chunks for a list of chat messages.
    ///
    /// For multimodal engines (v0.12.0+): calls run_prefill (synchronous) then
    /// run_decode_async (streaming callback).  Image data from the most-recent
    /// user message is passed as a kLiteRtLmInputDataTypeImage input preceding
    /// the text prompt (image → text ordering matches Android).
    ///
    /// For non-multimodal engines: uses generate_content_stream as before.
    func chatStream(
        messages:    [InferenceMessage],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard self.isLoaded else {
                continuation.finish(throwing: InferenceError.noModelLoaded)
                return
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }

                self.sessionLock.lock()
                let alreadyActive = self.sessionActive
                if !alreadyActive { self.sessionActive = true }
                self.sessionLock.unlock()

                guard !alreadyActive else {
                    engineLog.error("chatStream: rejected — session already active")
                    continuation.finish(throwing: InferenceError.busy)
                    return
                }

                defer {
                    self.sessionLock.lock()
                    self.sessionActive = false
                    self.sessionLock.unlock()
                    engineLog.debug("chatStream: defer — sessionActive cleared")
                }

                engineLog.info("chatStream: starting — \(messages.count) messages isMultimodal=\(self.isMultimodal)")

                if self.isMultimodal {
                    // ── Conversation API path (multimodal) ───────────────────────────────
                    // litert_lm_conversation_send_message_stream handles image preprocessing
                    // internally — the Session API cannot do this (it requires pre-processed
                    // patches and fails with "Image must be preprocessed before being used
                    // in SessionAdvanced").
                    //
                    // We lazily create `persistentConversation` (with the system message)
                    // on the first call and keep it alive across turns.  Each call sends
                    // only the newest user turn; the Conversation object maintains its own
                    // internal KV-cache across send_message calls.
                    do {
                        if self.persistentConversation == nil {
                            let sys = messages
                                .filter { $0.role == "system" }
                                .map    { $0.text }
                                .joined(separator: "\n")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            self.persistentConversation = try self.makeConversation(systemText: sys)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let conv = self.persistentConversation else {
                        continuation.finish(throwing: InferenceError.sessionCreationFailed)
                        return
                    }

                    // Find the next un-committed user turn.
                    let userMessages = messages.filter { $0.role == "user" }
                    let turnIndex    = self.committedConvTurnCount
                    guard turnIndex < userMessages.count else {
                        engineLog.debug("chatStream(mm): all \(userMessages.count) user turns already committed — nothing to do")
                        continuation.finish()
                        return
                    }
                    let userMsg = userMessages[turnIndex]
                    let msgJson = LiteRtLmEngine.buildConversationMessageJson(
                        text: userMsg.text, imageData: userMsg.imageData,
                        maxVisionDimension: self.maxVisionDimension
                    )
                    engineLog.debug("chatStream(mm): turn=\(turnIndex) hasImage=\(userMsg.imageData != nil) msgJson.count=\(msgJson.count)")

                    let innerStream = AsyncStream<String> { innerCont in
                        let ctx    = ConvStreamContext(continuation: innerCont)
                        let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()
                        // native-v0.12.0: send_message_stream also requires non-null optional_args.
                        let optArgs = litert_lm_conversation_optional_args_create()
                        let rc = msgJson.withCString { msgPtr in
                            litert_lm_conversation_send_message_stream(
                                conv, msgPtr, nil, optArgs, liteRtLmConvStreamCallback, ctxPtr
                            )
                        }
                        litert_lm_conversation_optional_args_delete(optArgs)
                        engineLog.debug("chatStream(mm): send_message_stream rc=\(rc)")
                        if rc != 0 {
                            // The callback will not fire — release the retained context to
                            // prevent a permanent leak and close the inner stream immediately.
                            Unmanaged<ConvStreamContext>.fromOpaque(ctxPtr).release()
                            innerCont.finish()
                        }
                    }

                    var fullText = ""
                    for await token in innerStream { fullText += token }
                    // Only advance committedConvTurnCount when the engine accepted the message.
                    // An empty response means send_message_stream failed (rc ≠ 0 or the
                    // callback fired an error path), so we skip the increment to keep
                    // committedConvTurnCount in sync with the engine's actual KV-cache state.
                    if !fullText.isEmpty {
                        self.committedConvTurnCount += 1
                    }
                    engineLog.debug("chatStream(mm): response \(fullText.count) chars committedConvTurnCount=\(self.committedConvTurnCount)")
                    engineLog.info("chatStream(mm): \(fullText.count) chars")
                    self.logBenchmark(conversation: conv)

                    let clean = fullText
                        .removingGemmaStopTokens()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { continuation.yield(clean) }
                    continuation.finish()
                    engineLog.info("chatStream(mm): continuation finished")

                } else {
                    // ── Session API path (non-multimodal) ────────────────────────────────
                    guard let session = self.persistentSession else {
                        continuation.finish(throwing: InferenceError.noModelLoaded)
                        return
                    }
                    let prompt = LiteRtLmEngine.buildGemmaPrompt(messages: messages)
                    engineLog.info("chatStream: prompt \(prompt.count) chars")

                    let promptBytes = ContiguousArray(
                        (prompt.utf8CString).map { UInt8(bitPattern: $0) }
                    )

                    let innerStream = AsyncStream<String> { innerCont in
                        let ctx = StreamContext(
                            continuation: innerCont,
                            inputBuffer:  promptBytes
                        )
                        let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                        ctx.inputBuffer.withUnsafeBufferPointer { textBuf in
                            let textInput = InputData(
                                type: kInputText,
                                data: UnsafeRawPointer(textBuf.baseAddress),
                                size: textBuf.count > 0 ? textBuf.count - 1 : 0
                            )
                            var input = textInput
                            engineLog.debug("chatStream: calling generate_content_stream (non-multimodal)")
                            let rc = litert_lm_session_generate_content_stream(
                                session, &input, 1, liteRtLmStreamCallback, ctxPtr
                            )
                            engineLog.debug("chatStream: generate_content_stream returned \(rc)")
                        }
                    }

                    var raw = ""
                    for await token in innerStream { raw += token }
                    engineLog.info("chatStream: raw output \(raw.count) chars")

                    let boundary = "<start_of_turn>model\n"
                    let clean: String
                    if let range = raw.range(of: boundary, options: .backwards) {
                        clean = String(raw[range.upperBound...]).removingGemmaStopTokens()
                        engineLog.info("chatStream: boundary found — response \(clean.count) chars")
                    } else {
                        clean = raw.removingGemmaStopTokens()
                        engineLog.warning("chatStream: no boundary found — raw stripped to \(clean.count) chars")
                    }

                    if !clean.isEmpty { continuation.yield(clean) }
                    continuation.finish()
                    engineLog.info("chatStream: continuation finished")
                }
            }
        }
    }

    /// Blocking (non-streaming) inference. Returns complete response string.
    /// Uses the persistent session created at load time — no session create/delete
    /// per call, which avoids the SDK bug where create_session hangs on 2nd use.
    func chat(
        messages:    [InferenceMessage],
        maxTokens:   Int   = 512,
        temperature: Float = 0.8
    ) throws -> String {
        guard isLoaded else { throw InferenceError.noModelLoaded }

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
            engineLog.debug("chat: inference complete — sessionActive cleared committed=\(self.committedMessageCount)")
        }

        // ── Multimodal: Conversation API ─────────────────────────────────────────
        // The Session API (generate_content) fails for raw image data with:
        //   "Image must be preprocessed before being used in SessionAdvanced"
        // The Conversation API handles preprocessing internally.
        if isMultimodal {
            if persistentConversation == nil {
                let sys = messages
                    .filter { $0.role == "system" }
                    .map    { $0.text }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                persistentConversation = try makeConversation(systemText: sys)
            }
            guard let conv = persistentConversation else {
                throw InferenceError.sessionCreationFailed
            }

            let userMessages = messages.filter { $0.role == "user" }
            let turnIndex    = committedConvTurnCount
            guard turnIndex < userMessages.count else {
                engineLog.debug("chat(mm): all \(userMessages.count) user turns already committed")
                return ""
            }
            let userMsg = userMessages[turnIndex]
            let msgJson = LiteRtLmEngine.buildConversationMessageJson(
                text: userMsg.text, imageData: userMsg.imageData,
                maxVisionDimension: maxVisionDimension
            )
            engineLog.debug("chat(mm): turn=\(turnIndex) hasImage=\(userMsg.imageData != nil) msgJson.count=\(msgJson.count)")

            // native-v0.12.0: send_message requires a non-null optional_args.
            guard let optArgs = litert_lm_conversation_optional_args_create() else {
                throw InferenceError.generationFailed("optional_args_create returned nil")
            }
            defer { litert_lm_conversation_optional_args_delete(optArgs) }
            engineLog.debug("chat(mm): calling send_message")
            let jsonResp: OpaquePointer? = msgJson.withCString { msgPtr in
                litert_lm_conversation_send_message(conv, msgPtr, nil, optArgs)
            }
            engineLog.debug("chat(mm): send_message returned — resp=\(jsonResp != nil ? "ok" : "nil")")

            guard let jsonResp else {
                // Do NOT increment committedConvTurnCount — the turn was not committed.
                throw InferenceError.generationFailed("conversation_send_message returned nil")
            }
            committedConvTurnCount += 1
            engineLog.debug("chat(mm): committedConvTurnCount=\(self.committedConvTurnCount)")
            logBenchmark(conversation: conv)
            defer { litert_lm_json_response_delete(jsonResp) }

            let rawJson = litert_lm_json_response_get_string(jsonResp)
                .map { String(cString: $0) } ?? ""
            engineLog.debug("chat(mm): rawJson len=\(rawJson.count)")

            // Extract the text value from the JSON response object.
            let text = convChunkText(rawJson) ?? rawJson
            engineLog.info("chat(mm): extracted text \(text.count) chars")
            return text.removingGemmaStopTokens()
                       .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // ── Non-multimodal: generate_content (prefill+decode in one call) ────────
        // Build only the NEW portion of the prompt — messages already committed
        // to the session's KV cache are skipped so we never double the context.
        let alreadyCommitted = committedMessageCount
        let newMessages      = Array(messages.dropFirst(alreadyCommitted))
        let prompt: String
        if alreadyCommitted == 0 {
            prompt = LiteRtLmEngine.buildGemmaPrompt(messages: newMessages)
        } else {
            let latestUser = newMessages.last(where: { $0.role == "user" })?.text ?? ""
            prompt = "<end_of_turn>\n<start_of_turn>user\n\(latestUser)<end_of_turn>\n<start_of_turn>model\n"
        }
        engineLog.debug("chat: turn \(alreadyCommitted == 0 ? "1(full)" : "N(incr)") prompt \(prompt.count) chars — calling generate_content")

        guard let session = persistentSession else {
            throw InferenceError.noModelLoaded
        }
        let responses: OpaquePointer?
        responses = prompt.withCString { cStr in
            var input = InputData(
                type: kInputText,
                data: UnsafeRawPointer(cStr),
                size: strlen(cStr)
            )
            return litert_lm_session_generate_content(session, &input, 1)
        }
        // Advance committed count — all messages are now in the session KV-cache.
        committedMessageCount = messages.count
        engineLog.debug("chat: generate_content returned — responses=\(responses != nil ? "ok" : "nil") committedNow=\(self.committedMessageCount)")

        guard let responses else {
            throw InferenceError.generationFailed("generate_content returned nil")
        }
        defer { litert_lm_responses_delete(responses) }

        let raw = litert_lm_responses_get_response_text_at(responses, 0)
            .map { String(cString: $0) } ?? ""
        engineLog.info("chat: raw output \(raw.count) chars")

        let boundary = "<start_of_turn>model\n"
        let response: String
        if let range = raw.range(of: boundary, options: .backwards) {
            response = String(raw[range.upperBound...])
        } else {
            response = raw
        }
        return response.removingGemmaStopTokens()
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

        // 1. Strip complete special tokens.
        for token in GemmaStopTokenFilter.tokens {
            s = s.replacingOccurrences(of: token, with: "")
        }

        // 2. Strip any trailing PARTIAL special token.
        //    The SDK sometimes cuts the stream mid-token (e.g. "<start_of_"
        //    instead of the full "<start_of_turn>"), leaving a visible fragment.
        for token in GemmaStopTokenFilter.tokens {
            // Walk from longest possible prefix down to 1 character.
            for prefixLen in stride(from: token.count - 1, through: 1, by: -1) {
                let prefix = String(token.prefix(prefixLen))
                if s.hasSuffix(prefix) {
                    s = String(s.dropLast(prefixLen))
                    break   // only strip one partial token per full-token candidate
                }
            }
        }

        // 3. Strip residual role labels left behind after <start_of_turn> removal.
        s = s.replacingOccurrences(of: "\nmodel\n", with: "\n")
        s = s.replacingOccurrences(of: "\nuser\n",  with: "\n")
        if s.hasPrefix("model\n") { s = String(s.dropFirst(6)) }
        if s.hasPrefix("user\n")  { s = String(s.dropFirst(5)) }

        return s
    }
}

// MARK: - Gemma special-token constants

/// Namespace for Gemma stop-token strings used by `removingGemmaStopTokens()`.
private enum GemmaStopTokenFilter {
    static let tokens: [String] = [
        // Gemma 3 turn tokens
        "<end_of_turn>", "<start_of_turn>", "</start_of_turn>",
        // Gemma 4 turn tokens
        "<turn|>", "<|turn>",
        // Common EOS tokens
        "<eos>", "</s>",
        // Gemma 4 tool / function-call fences
        "<|tool_call>", "<tool_call|>",
        "<|tool_response>", "<tool_response|>",
    ]
}
