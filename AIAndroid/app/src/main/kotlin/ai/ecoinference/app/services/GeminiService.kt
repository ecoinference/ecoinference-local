package ai.ecoinference.app.services

import ai.ecoinference.app.inference.InferenceMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.Base64
import java.util.concurrent.TimeUnit

class GeminiServiceException(message: String) : Exception(message)

/**
 * Calls Google's Gemini API — the cloud tier of the LLM router.
 * Takes the same [InferenceMessage] shape InferenceService uses so call sites
 * can swap local/cloud without reshaping the conversation. Mirrors iOS
 * GeminiService.swift.
 */
object GeminiService {

    /** "latest" alias so we don't need to track Google's dot-version bumps. */
    const val DEFAULT_MODEL = "gemini-flash-latest"

    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    /** Non-streaming chat completion against Gemini. */
    suspend fun chat(
        messages: List<InferenceMessage>,
        systemPrompt: String? = null,
        apiKey: String,
        model: String = DEFAULT_MODEL,
        maxTokens: Int = 2048,
        temperature: Float = 0.8f,
    ): String = withContext(Dispatchers.IO) {
        if (apiKey.isBlank()) {
            throw GeminiServiceException("No Gemini API key set. Add one in Settings → Cloud AI.")
        }

        val body = GeminiRequest(
            contents = messages.map { it.toGeminiContent() },
            systemInstruction = systemPrompt?.takeIf { it.isNotBlank() }
                ?.let { GeminiSystemInstruction(listOf(GeminiPart(text = it))) },
            generationConfig = GeminiGenerationConfig(temperature, maxTokens),
        )
        val requestJson = json.encodeToString(body)

        val request = Request.Builder()
            .url("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent")
            .addHeader("Content-Type", "application/json")
            // Header (not query string) keeps the key out of URLs/logs.
            .addHeader("x-goog-api-key", apiKey)
            .post(requestJson.toRequestBody("application/json".toMediaType()))
            .build()

        client.newCall(request).execute().use { response ->
            val responseBody = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw GeminiServiceException("Gemini API error ${response.code}: $responseBody")
            }
            val parsed: GeminiResponse = try {
                json.decodeFromString(responseBody)
            } catch (e: Exception) {
                throw GeminiServiceException("Failed to decode Gemini response: ${e.message}")
            }
            parsed.candidates?.firstOrNull()?.content?.parts?.firstOrNull()?.text
                ?: throw GeminiServiceException("Gemini returned an empty response.")
        }
    }
}

private fun InferenceMessage.toGeminiContent(): GeminiContent {
    // Gemini uses "model" for assistant turns, "user" for everything else.
    val role = if (this.role == "assistant") "model" else "user"
    val parts = buildList {
        if (text.isNotEmpty()) add(GeminiPart(text = text))
        imageBytes?.let {
            add(GeminiPart(inlineData = GeminiInlineData(
                mimeType = "image/jpeg",
                data     = Base64.getEncoder().encodeToString(it),
            )))
        }
    }
    return GeminiContent(role, parts)
}

// MARK: - Request models

@Serializable
private data class GeminiRequest(
    val contents: List<GeminiContent>,
    val systemInstruction: GeminiSystemInstruction? = null,
    val generationConfig: GeminiGenerationConfig,
)

@Serializable
private data class GeminiSystemInstruction(val parts: List<GeminiPart>)

@Serializable
private data class GeminiGenerationConfig(val temperature: Float, val maxOutputTokens: Int)

@Serializable
private data class GeminiContent(val role: String, val parts: List<GeminiPart>)

/** Exactly one of [text] / [inlineData] is set per part. */
@Serializable
private data class GeminiPart(
    val text: String? = null,
    val inlineData: GeminiInlineData? = null,
)

@Serializable
private data class GeminiInlineData(val mimeType: String, val data: String)

// MARK: - Response models

@Serializable
private data class GeminiResponse(val candidates: List<GeminiCandidate>? = null)

@Serializable
private data class GeminiCandidate(val content: GeminiResponseContent? = null)

@Serializable
private data class GeminiResponseContent(val parts: List<GeminiResponsePart>? = null)

@Serializable
private data class GeminiResponsePart(val text: String? = null)
