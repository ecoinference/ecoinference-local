package ai.ecoinference.app.models

/**
 * Single source of truth for all downloadable models.
 *
 * Only Android-compatible models are included here.
 * Unlike iOS (native-v0.12.0), the Android LiteRT-LM Kotlin SDK handles
 * E4B vision correctly — both E2B and E4B support full multimodal input.
 */
object ModelCatalog {

    private const val HF_BASE = "https://huggingface.co"
    private const val PI_BASE = "https://models.example.invalid"

    // ── Gemma 4 — Android (.litertlm, LiteRT-LM Kotlin SDK) ──────────────────

    private val gemma4E2b = ModelInfo(
        id               = "gemma4-e2b-it",
        displayName      = "Gemma 4 E2B",
        description      = "Gemma 4 effective-2B, instruction-tuned. " +
                           "Good balance of speed and quality (~2.6 GB).",
        parameterCount   = "E2B",
        fileSizeMb       = 2588,
        downloadUrl      = "$PI_BASE/gemma-4-E2B-it.litertlm",
        fileName         = "gemma-4-E2B-it.litertlm",
        requiresHfToken  = false,
        licenseUrl       = "$HF_BASE/litert-community/gemma-4-E2B-it-litert-lm",
        platform         = "android",
        gemmaVersion     = 4,
        supportsVision   = true,   // SigLIP encoder in bundle
        supportsImageInput = true, // Android SDK supports E2B vision fully
        maxContextTokens = 4096,
    )

    private val gemma4E4b = ModelInfo(
        id               = "gemma4-e4b-it",
        displayName      = "Gemma 4 E4B",
        description      = "Gemma 4 effective-4B, instruction-tuned. " +
                           "Best quality; needs ≥6 GB RAM and ~3.7 GB storage.",
        parameterCount   = "E4B",
        fileSizeMb       = 3659,
        downloadUrl      = "$PI_BASE/gemma-4-E4B-it.litertlm",
        fileName         = "gemma-4-E4B-it.litertlm",
        requiresHfToken  = false,
        licenseUrl       = "$HF_BASE/litert-community/gemma-4-E4B-it-litert-lm",
        platform         = "android",
        gemmaVersion     = 4,
        supportsVision   = true,   // SigLIP encoder in bundle
        supportsImageInput = true, // Android SDK supports E4B vision (unlike iOS native-v0.12.0)
        maxContextTokens = 4096,
    )

    /** All models valid for this Android app. */
    val all: List<ModelInfo> = listOf(gemma4E2b, gemma4E4b)

    fun findById(id: String): ModelInfo? = all.firstOrNull { it.id == id }
}
