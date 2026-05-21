package com.gemma4.aiserver.catalog

import com.gemma4.aiserver.model.ModelInfo

/**
 * Single source of truth for all downloadable models.
 *
 * Platform field values:
 *   "android" — .litertlm models (Gemma 4, LiteRT backend)
 *   "ios"     — .task models (Gemma 3 / Gemma 3n, MediaPipe backend)
 *   "all"     — works on both
 *
 * This server is Android-only, so only "android" and "all" entries
 * are served to AIClient.  The "ios" entries are included so the
 * catalog definition can be shared with a future iOS native build.
 */
object ModelCatalog {

    private const val HF_BASE =
        "https://huggingface.co"

    private const val PI_BASE =
        "https://models.example.invalid"

    // ── Gemma 4 — Android (.litertlm, LiteRT) ────────────────────────────────
    // Requires MediaPipe Tasks GenAI 0.10.20+ on Android API 26+.
    //
    // Gemma 4 is Apache 2.0 but hosted on HuggingFace with gated access —
    // users must accept the licence once at the model page before the
    // download URL becomes accessible.  The server returns HTTP 401 if they
    // have not yet done so; AIClient uses licenseUrl to guide them there.

    private val gemma4E2b = ModelInfo(
        id = "gemma4-e2b-it",
        displayName = "Gemma 4 E2B",
        description = "Gemma 4 effective-2B, instruction-tuned. " +
                "Good balance of speed and quality (~2.6 GB).",
        parameterCount = "E2B",
        fileSizeMb = 2580,
        downloadUrl = "$PI_BASE/gemma-4-E2B-it.litertlm",
        fileName = "gemma-4-E2B-it.litertlm",
        requiresHfToken = false,
        licenseUrl = "$HF_BASE/litert-community/gemma-4-E2B-it-litert-lm",
        platform = "android",
        gemmaVersion = 4,
        supportsVision = true,   // .litertlm bundle includes the SigLIP encoder
    )

    private val gemma4E4b = ModelInfo(
        id = "gemma4-e4b-it",
        displayName = "Gemma 4 E4B",
        description = "Gemma 4 effective-4B, instruction-tuned. " +
                "Best quality; needs ≥6 GB RAM and ~3.7 GB storage.",
        parameterCount = "E4B",
        fileSizeMb = 3650,
        downloadUrl = "$PI_BASE/gemma-4-E4B-it.litertlm",
        fileName = "gemma-4-E4B-it.litertlm",
        requiresHfToken = false,
        licenseUrl = "$HF_BASE/litert-community/gemma-4-E4B-it-litert-lm",
        platform = "android",
        gemmaVersion = 4,
        supportsVision = true,   // .litertlm bundle includes the SigLIP encoder
    )

    // ── Gemma 3n — iOS (.task, MediaPipe) ────────────────────────────────────
    // Included for catalog completeness; not served by this Android server.

    private val gemma3nE2b = ModelInfo(
        id = "gemma3n-e2b-it",
        displayName = "Gemma 3n E2B",
        description = "Gemma 3 Nano E2B, instruction-tuned. " +
                "Best option for iOS (~3.1 GB). Requires HuggingFace token.",
        parameterCount = "E2B",
        fileSizeMb = 3100,
        downloadUrl = "$HF_BASE/google/gemma-3n-E2B-it-litert-preview" +
                "/resolve/main/gemma-3n-E2B-it-int4.task",
        fileName = "gemma-3n-E2B-it-int4.task",
        requiresHfToken = true,
        platform = "ios",
        gemmaVersion = 3,
    )

    private val gemma3_1b = ModelInfo(
        id = "gemma3-1b-it",
        displayName = "Gemma 3 1B",
        description = "Gemma 3 1B, instruction-tuned. " +
                "Fastest and smallest option (~0.5 GB). No token required.",
        parameterCount = "1B",
        fileSizeMb = 500,
        downloadUrl = "$HF_BASE/litert-community/Gemma3-1B-IT" +
                "/resolve/main/gemma3-1b-it-int4.task",
        fileName = "gemma3-1b-it-int4.task",
        requiresHfToken = false,
        platform = "ios",
        gemmaVersion = 3,
    )

    /** All models known to this build. */
    private val all = listOf(gemma4E2b, gemma4E4b, gemma3nE2b, gemma3_1b)

    /** Models valid for this Android server (platform == "android" or "all"). */
    val androidModels: List<ModelInfo> =
        all.filter { it.platform == "android" || it.platform == "all" }

    fun findById(id: String): ModelInfo? = all.firstOrNull { it.id == id }

    fun isAndroidModel(id: String): Boolean =
        findById(id)?.let { it.platform == "android" || it.platform == "all" } ?: false
}
