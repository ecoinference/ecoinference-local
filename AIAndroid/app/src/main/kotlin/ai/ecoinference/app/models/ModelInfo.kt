package ai.ecoinference.app.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A single entry in the model catalogue. */
@Serializable
data class ModelInfo(
    val id: String,
    @SerialName("display_name")   val displayName: String,
    val description: String = "",
    @SerialName("parameter_count") val parameterCount: String = "",
    @SerialName("file_size_mb")   val fileSizeMb: Int,
    @SerialName("file_name")      val fileName: String,
    @SerialName("license_url")    val licenseUrl: String? = null,
    /** "android" | "ios" | "all" */
    val platform: String,
    @SerialName("gemma_version")  val gemmaVersion: Int = 4,
    /** True when the .litertlm bundle includes a SigLIP vision encoder. */
    @SerialName("supports_vision") val supportsVision: Boolean = false,
    /**
     * Whether the UI should offer image attachment for this model.
     * Mirrors iOS supportsImageInput — on Android both E2B and E4B support
     * image input correctly (no XNNPack/STABLEHLO_COMPOSITE gaps on Android).
     */
    @SerialName("supports_image_input") val supportsImageInput: Boolean = supportsVision,
    /** KV-cache token budget. Must not exceed the model's compiled limit. */
    @SerialName("max_context_tokens") val maxContextTokens: Int = 4096,
    // Live state — populated by AppState before presenting to the UI.
    val downloaded: Boolean = false,
    val loaded: Boolean = false,
) {
    /** Human-readable size, e.g. "2.6 GB". */
    val sizeLabel: String
        get() = String.format("%.1f GB", fileSizeMb / 1024.0)
}
