package com.gemma4.aiserver.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

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
    @SerialName("max_tokens") val maxTokens: Int = 1024,
)

@Serializable
data class LoadResponse(
    @SerialName("model_id") val modelId: String,
    val status: String,   // "loading" | "loaded" | "error"
    val error: String? = null,
)

// ── OpenAI-compatible chat completions ────────────────────────────────────────

@Serializable
data class ChatMessage(
    val role: String,
    val content: String,
)

@Serializable
data class ChatCompletionRequest(
    val model: String,
    val messages: List<ChatMessage>,
    @SerialName("max_tokens") val maxTokens: Int = 512,
    val temperature: Float = 0.8f,
    val stream: Boolean = false,
)

@Serializable
data class CompletionRequest(
    val model: String,
    val prompt: String,
    @SerialName("max_tokens") val maxTokens: Int = 512,
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
