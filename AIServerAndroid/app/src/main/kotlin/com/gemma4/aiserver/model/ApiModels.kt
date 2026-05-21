package com.gemma4.aiserver.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// ── Health ────────────────────────────────────────────────────────────────────

@Serializable
data class HealthResponse(
    val status: String = "ok",
    @SerialName("model_loaded") val modelLoaded: Boolean,
    @SerialName("model_id") val modelId: String? = null,
    val port: Int,
    @SerialName("download_active") val downloadActive: Boolean,
    val version: String = "1.0.0",
)

// ── Catalog ───────────────────────────────────────────────────────────────────

@Serializable
data class CatalogResponse(val models: List<ModelInfo>)

// ── Download ──────────────────────────────────────────────────────────────────

@Serializable
data class DownloadRequest(
    @SerialName("model_id") val modelId: String,
    /** Optional HF token — only needed if the model page returns 401. */
    @SerialName("hf_token") val hfToken: String? = null,
)

@Serializable
data class DownloadStartedResponse(
    @SerialName("model_id") val modelId: String,
    val status: String = "downloading",
)

@Serializable
data class DownloadProgress(
    @SerialName("model_id") val modelId: String,
    /** "downloading" | "complete" | "error" | "cancelled" */
    val status: String,
    val percent: Int = 0,
    @SerialName("bytes_received") val bytesReceived: Long = 0L,
    @SerialName("total_bytes") val totalBytes: Long = 0L,
    val error: String? = null,
)

// ── Model load/unload ─────────────────────────────────────────────────────────

@Serializable
data class LoadRequest(
    @SerialName("model_id") val modelId: String,
    @SerialName("use_gpu") val useGpu: Boolean = false,
    /** KV-cache budget (input + history + output combined).
     *  The model binary is the hard ceiling; default 8192 uses the
     *  full context window of the Gemma 4 E2B .litertlm export. */
    @SerialName("max_num_tokens") val maxNumTokens: Int = 8192,
)

@Serializable
data class LoadResponse(
    @SerialName("model_id") val modelId: String,
    val status: String,   // "loading" | "loaded" | "error"
    val error: String? = null,
)

// ── OpenAI-compatible chat completions ────────────────────────────────────────

/**
 * A single turn in a chat conversation.
 *
 * [content] is polymorphic per the OpenAI vision spec:
 *   - text-only: `"content": "Hello"`   → [JsonPrimitive]
 *   - multimodal: `"content": [{"type":"text","text":"…"},
 *                               {"type":"image_url","image_url":{"url":"data:…"}}]`
 *                                        → [JsonArray]
 *
 * Use [extractText] and [extractImageBytes] to get the respective parts.
 * When building a response message, pass [JsonPrimitive] for a plain string.
 */
@Serializable
data class ChatMessage(
    val role: String,
    val content: JsonElement,
)

/** Returns the text portion of [content] regardless of its format. */
fun ChatMessage.extractText(): String = when (val c = content) {
    is JsonPrimitive -> c.contentOrNull ?: ""
    is JsonArray     -> c.firstOrNull {
                            it.jsonObject["type"]?.jsonPrimitive?.contentOrNull == "text"
                        }?.jsonObject?.get("text")?.jsonPrimitive?.contentOrNull ?: ""
    else             -> ""
}

/**
 * Returns raw image bytes decoded from the `image_url` part of a multimodal
 * [content] array, or `null` if the message contains no image.
 *
 * Supports `data:image/<type>;base64,<data>` URLs as sent by AIClient.
 */
fun ChatMessage.extractImageBytes(): ByteArray? {
    val arr = content as? JsonArray ?: return null
    val url = arr.firstOrNull {
        it.jsonObject["type"]?.jsonPrimitive?.contentOrNull == "image_url"
    }?.jsonObject?.get("image_url")?.jsonObject?.get("url")?.jsonPrimitive?.contentOrNull
        ?: return null
    val base64 = url.substringAfter("base64,", "")
    if (base64.isEmpty()) return null
    return try {
        java.util.Base64.getDecoder().decode(base64)
    } catch (_: IllegalArgumentException) {
        null
    }
}

@Serializable
data class ChatCompletionRequest(
    val model: String,
    val messages: List<ChatMessage>,
    /** Max tokens to generate in this response (not counting the prompt). */
    @SerialName("max_tokens") val maxTokens: Int = 2048,
    val temperature: Float = 0.8f,
    val stream: Boolean = false,
)

@Serializable
data class CompletionRequest(
    val model: String,
    val prompt: String,
    /** Max tokens to generate in this response (not counting the prompt). */
    @SerialName("max_tokens") val maxTokens: Int = 2048,
    val temperature: Float = 0.8f,
    val stream: Boolean = false,
)

@Serializable
data class ChatCompletionResponse(
    val id: String,
    val `object`: String = "chat.completion",
    val model: String,
    val choices: List<ChatChoice>,
    val usage: TokenUsage,
)

@Serializable
data class ChatChoice(
    val index: Int = 0,
    val message: ChatMessage,
    @SerialName("finish_reason") val finishReason: String = "stop",
)

@Serializable
data class CompletionResponse(
    val id: String,
    val `object`: String = "text_completion",
    val model: String,
    val choices: List<CompletionChoice>,
    val usage: TokenUsage,
)

@Serializable
data class CompletionChoice(
    val index: Int = 0,
    val text: String,
    @SerialName("finish_reason") val finishReason: String = "stop",
)

@Serializable
data class TokenUsage(
    @SerialName("prompt_tokens") val promptTokens: Int,
    @SerialName("completion_tokens") val completionTokens: Int,
    @SerialName("total_tokens") val totalTokens: Int,
)

// ── SSE delta (streaming) ─────────────────────────────────────────────────────

@Serializable
data class ChatChunk(
    val id: String,
    val `object`: String = "chat.completion.chunk",
    val model: String,
    val choices: List<ChunkChoice>,
)

@Serializable
data class ChunkChoice(
    val index: Int = 0,
    val delta: ChunkDelta,
    @SerialName("finish_reason") val finishReason: String? = null,
)

@Serializable
data class ChunkDelta(
    val role: String? = null,
    val content: String? = null,
)

// ── Error ─────────────────────────────────────────────────────────────────────

@Serializable
data class ErrorResponse(val error: String)
