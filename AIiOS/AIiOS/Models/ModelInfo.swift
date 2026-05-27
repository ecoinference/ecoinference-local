import Foundation

/// A single entry in the model catalog.
struct ModelInfo: Codable, Identifiable {
    let id: String
    let displayName: String
    let fileName: String
    /// Approximate model size in megabytes (for display).
    let fileSizeMb: Int
    /// "ios" | "android" | "all"
    let platform: String
    let requiresHfToken: Bool
    let licenseUrl: String?
    let downloadUrl: String
    var downloaded: Bool
    var loaded: Bool
    /// Whether to load in multimodal mode (Conversation API). True does NOT
    /// guarantee the bundle can process image payloads — see supportsImageInput.
    let supportsVision: Bool
    /// Whether the UI should offer image attachment for this model.
    /// A model may use the Conversation API (supportsVision=true) for better
    /// text quality while its LiteRT-LM bundle lacks a working SigLIP encoder.
    let supportsImageInput: Bool
    /// Whether the .litertlm bundle includes a speculative-decoding draft model.
    /// Only enable when confirmed — passing true for a bundle without a draft
    /// model causes send_message to return nil silently.
    let supportsSpeculativeDecoding: Bool
    /// KV-cache token budget to pass to litert_lm_engine_settings_set_max_num_tokens.
    /// Must not exceed the value the .litertlm was compiled with — the engine
    /// silently clamps to its compiled limit, but requesting too many tokens can
    /// cause KV-cache allocation failures at first send_message.
    let maxContextTokens: Int

    enum CodingKeys: String, CodingKey {
        case id
        case displayName    = "display_name"
        case fileName       = "file_name"
        case fileSizeMb     = "file_size_mb"
        case platform
        case requiresHfToken = "requires_hf_token"
        case licenseUrl     = "license_url"
        case downloadUrl    = "download_url"
        case downloaded
        case loaded
        case supportsVision      = "supports_vision"
        case supportsImageInput  = "supports_image_input"
        case supportsSpeculativeDecoding = "supports_speculative_decoding"
        case maxContextTokens = "max_context_tokens"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        displayName     = try c.decode(String.self, forKey: .displayName)
        fileName        = try c.decode(String.self, forKey: .fileName)
        fileSizeMb      = try c.decode(Int.self,    forKey: .fileSizeMb)
        platform        = try c.decode(String.self, forKey: .platform)
        requiresHfToken = try c.decode(Bool.self,   forKey: .requiresHfToken)
        licenseUrl      = try c.decodeIfPresent(String.self, forKey: .licenseUrl)
        downloadUrl     = try c.decode(String.self, forKey: .downloadUrl)
        downloaded      = try c.decodeIfPresent(Bool.self, forKey: .downloaded) ?? false
        loaded          = try c.decodeIfPresent(Bool.self, forKey: .loaded)     ?? false
        supportsVision              = try c.decodeIfPresent(Bool.self, forKey: .supportsVision)              ?? false
        supportsImageInput          = try c.decodeIfPresent(Bool.self, forKey: .supportsImageInput)          ?? supportsVision
        supportsSpeculativeDecoding = try c.decodeIfPresent(Bool.self, forKey: .supportsSpeculativeDecoding) ?? false
        maxContextTokens            = try c.decodeIfPresent(Int.self,  forKey: .maxContextTokens) ?? 4096
    }

    /// Memberwise init used by ModelCatalog.
    init(id: String, displayName: String, fileName: String, fileSizeMb: Int,
         platform: String, requiresHfToken: Bool, licenseUrl: String?,
         downloadUrl: String, downloaded: Bool, loaded: Bool,
         supportsVision: Bool = false, supportsImageInput: Bool? = nil,
         supportsSpeculativeDecoding: Bool = false,
         maxContextTokens: Int = 4096) {
        self.id              = id
        self.displayName     = displayName
        self.fileName        = fileName
        self.fileSizeMb      = fileSizeMb
        self.platform        = platform
        self.requiresHfToken = requiresHfToken
        self.licenseUrl      = licenseUrl
        self.downloadUrl     = downloadUrl
        self.downloaded      = downloaded
        self.loaded          = loaded
        self.supportsVision              = supportsVision
        self.supportsImageInput          = supportsImageInput ?? supportsVision
        self.supportsSpeculativeDecoding = supportsSpeculativeDecoding
        self.maxContextTokens            = maxContextTokens
    }

    /// Size formatted for display, e.g. "2.5 GB".
    var sizeLabel: String {
        let gb = Double(fileSizeMb) / 1024.0
        return String(format: "%.1f GB", gb)
    }
}

// MARK: - Catalog

enum ModelCatalog {

    // ── iOS models (.litertlm via LiteRT-LM C API) ────────────────────────────

    private static let piBase = "https://models.example.invalid/models"
    private static let hfBase = "https://huggingface.co"

    static let all: [ModelInfo] = [
        ModelInfo(
            id:              "gemma4-e2b-it",
            displayName:     "Gemma 4 E2B",
            fileName:        "gemma-4-E2B-it.litertlm",
            fileSizeMb:      2588,
            platform:        "ios",
            requiresHfToken: false,
            licenseUrl:      "\(hfBase)/litert-community/gemma-4-E2B-it-litert-lm",
            downloadUrl:     "\(piBase)/gemma-4-E2B-it.litertlm",
            downloaded:      false,
            loaded:          false,
            supportsVision:              true,  // .litertlm bundle includes the SigLIP encoder
            supportsSpeculativeDecoding: true,  // confirmed: 21→24 tok/s
            maxContextTokens:            4096
        ),
        ModelInfo(
            id:              "gemma4-e4b-it",
            displayName:     "Gemma 4 E4B",
            fileName:        "gemma-4-E4B-it.litertlm",
            fileSizeMb:      3659,  // actual: 3,659,530,240 bytes
            platform:        "ios",
            requiresHfToken: false,
            licenseUrl:      "\(hfBase)/litert-community/gemma-4-E4B-it-litert-lm",
            downloadUrl:     "\(piBase)/gemma-4-E4B-it.litertlm",
            downloaded:      false,
            loaded:          false,
            // supportsVision=true loads via the Conversation API (needed for Gemma 4 prompt format).
            // supportsImageInput=false disables the image attachment UI — E4B's vision encoder
            // is incompatible with iOS LiteRT-LM native-v0.12.0:
            //   • Original model_type → STABLEHLO_COMPOSITE executor → fails (op not in iOS dylib)
            //   • Patched model_type "tZ4Y" → TFLite/XNNPack executor → fails (162/1477 ops in
            //     E4B's larger SigLIP encoder are not delegatable; XNNPack reshape fails at runtime)
            // E2B works because its smaller encoder uses ops fully supported by this XNNPack build.
            // Fix requires a newer iOS LiteRT-LM library from Google with broader XNNPack coverage.
            // supportsVision=false: E4B's Conversation API path fails on iOS LiteRT-LM
            // native-v0.12.0 — the llm_litert_compiled_model_executor and vision encoder both
            // hit "Failed to allocate tensors" due to STABLEHLO_COMPOSITE / XNNPack op gaps
            // in the iOS build (E4B's larger SigLIP encoder uses 162 non-XNNPack-delegatable
            // ops; E2B's smaller encoder is fully supported). Text works via the session path.
            // Re-enable supportsVision when a newer iOS LiteRT-LM library supports E4B's ops.
            supportsVision:              false,
            supportsImageInput:          false,
            supportsSpeculativeDecoding: false,
            maxContextTokens:            4096
        ),
    ]

    static func find(id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}
