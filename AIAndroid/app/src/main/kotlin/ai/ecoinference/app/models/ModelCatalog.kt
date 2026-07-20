package ai.ecoinference.app.models

/**
 * Single source of truth for all downloadable models.
 *
 * Only Android-compatible models are included here.
 * Unlike iOS (native-v0.12.0), the Android LiteRT-LM Kotlin SDK handles
 * E4B vision correctly — both E2B and E4B support full multimodal input.
 */
object ModelCatalog {

    // ── Gemma 4 — Android (.litertlm, LiteRT-LM Kotlin SDK) ──────────────────

    private val gemma4E2b = ModelInfo(
        id               = "gemma4-e2b-it",
        displayName      = "Gemma 4 E2B",
        description      = "Gemma 4 effective-2B, instruction-tuned. " +
                           "Good balance of speed and quality (~2.6 GB).",
        parameterCount   = "E2B",
        fileSizeMb       = 2588,
        fileName         = "gemma-4-E2B-it.litertlm",
        licenseUrl       = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm",
        platform         = "android",
        gemmaVersion     = 4,
        supportsVision   = true,
        supportsImageInput = true,
        maxContextTokens = 4096,
    )

    private val gemma4E4b = ModelInfo(
        id               = "gemma4-e4b-it",
        displayName      = "Gemma 4 E4B",
        description      = "Gemma 4 effective-4B, instruction-tuned. " +
                           "Best quality; needs ≥6 GB RAM and ~3.7 GB storage.",
        parameterCount   = "E4B",
        fileSizeMb       = 3659,
        fileName         = "gemma-4-E4B-it.litertlm",
        licenseUrl       = "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm",
        platform         = "android",
        gemmaVersion     = 4,
        supportsVision   = true,
        supportsImageInput = true,
        maxContextTokens = 4096,
    )

    /** All models valid for this Android app. */
    val all: List<ModelInfo> = listOf(gemma4E2b, gemma4E4b)

    fun findById(id: String): ModelInfo? = all.firstOrNull { it.id == id }
}
