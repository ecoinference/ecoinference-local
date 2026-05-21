package com.gemma4.aiserver.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A single entry in the model catalogue. */
@Serializable
data class ModelInfo(
    val id: String,
    @SerialName("display_name") val displayName: String,
    val description: String,
    @SerialName("parameter_count") val parameterCount: String,
    @SerialName("file_size_mb") val fileSizeMb: Int,
    @SerialName("download_url") val downloadUrl: String,
    @SerialName("file_name") val fileName: String,
    @SerialName("requires_hf_token") val requiresHfToken: Boolean,
    /** HuggingFace model page URL — shown to the user when a 401/403 is
     *  returned so they can accept the licence with one tap. Null for models
     *  that never require auth. */
    @SerialName("license_url") val licenseUrl: String? = null,
    /** "android" | "ios" | "all" */
    val platform: String,
    @SerialName("gemma_version") val gemmaVersion: Int,
    /** True when the model's .litertlm bundle includes a vision encoder (SigLIP).
     *  Drives visionBackend / maxNumImages in EngineConfig so the engine is
     *  correctly initialised before image input is passed to it. */
    @SerialName("supports_vision") val supportsVision: Boolean = false,
    // Live state — populated by the server before sending to AIClient.
    val downloaded: Boolean = false,
    val loaded: Boolean = false,
)
