package com.gemma4.aiserver.inference

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Wraps the MediaPipe Tasks GenAI [LlmInference] API directly.
 *
 * No flutter_gemma intermediary — this gives immediate access to every
 * option in the native SDK and tracks Google's release cadence without
 * waiting for a wrapper library update.
 *
 * Gemma chat prompt format (all Gemma instruction-tuned variants):
 *   <start_of_turn>user
 *   {optional system instruction}
 *
 *   {user message}<end_of_turn>
 *   <start_of_turn>model
 *   {assistant reply}<end_of_turn>
 *   <start_of_turn>user
 *   ...
 *   <start_of_turn>model
 *
 * The trailing "<start_of_turn>model\n" signals the model to generate.
 */
class InferenceRepository(private val context: Context) {

    private var llmInference: LlmInference? = null
    private var _loadedModelId: String? = null
    private var _modelPath: String? = null

    val isLoaded: Boolean get() = llmInference != null
    val loadedModelId: String? get() = _loadedModelId

    // ── Load / unload ─────────────────────────────────────────────────────────

    /**
     * Loads a model from [modelPath] on disk.
     *
     * This is a blocking operation (MediaPipe maps the weight file into memory)
     * and should be called from a non-UI coroutine. The previous model is
     * unloaded automatically before loading the new one.
     *
     * @param modelId   Catalogue ID — stored for status reporting.
     * @param modelPath Absolute path to the .litertlm file.
     * @param useGpu    When true, prefers the GPU backend (LiteRT accelerated).
     *                  Falls back to CPU automatically if GPU is unavailable.
     * @param maxTokens Maximum token budget for generation sessions.
     */
    suspend fun load(
        modelId: String,
        modelPath: String,
        useGpu: Boolean = false,
        maxTokens: Int = 1024,
    ) = withContext(Dispatchers.IO) {
        // Unload any previously loaded model first.
        unload()

        val file = File(modelPath)
        require(file.exists()) { "Model file not found: $modelPath" }
        require(file.length() > 1024 * 1024) {
            "Model file too small (${file.length()} bytes) — partial download?"
        }

        val options = LlmInferenceOptions.builder()
            .setModelPath(modelPath)
            .setMaxTokens(maxTokens)
            .setPreferredBackend(
                if (useGpu) LlmInference.Backend.GPU
                else LlmInference.Backend.CPU
            )
            .build()

        llmInference = LlmInference.createFromOptions(context, options)
        _loadedModelId = modelId
        _modelPath = modelPath
    }

    /** Closes the native inference session and frees resources. */
    fun unload() {
        llmInference?.close()
        llmInference = null
        _loadedModelId = null
        _modelPath = null
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    /**
     * Generates a response for [messages] and returns the full text.
     * Blocking — call from Dispatchers.IO.
     */
    suspend fun chat(
        messages: List<Map<String, String>>,
        maxTokens: Int = 512,
        temperature: Float = 0.8f,
    ): String = withContext(Dispatchers.IO) {
        val engine = llmInference
            ?: throw InferenceException("No model loaded. Call load() first.")

        val prompt = buildGemmaPrompt(messages)
        engine.generateResponse(prompt)
    }

    /**
     * Streaming variant of [chat].
     *
     * Wraps the callback-based [LlmInference.generateResponseAsync] in a
     * [callbackFlow] so callers can use idiomatic Kotlin Flow collection,
     * including coroutine cancellation.
     */
    fun chatStream(
        messages: List<Map<String, String>>,
        maxTokens: Int = 512,
        temperature: Float = 0.8f,
    ): Flow<String> = callbackFlow {
        val engine = llmInference
            ?: throw InferenceException("No model loaded. Call load() first.")

        val prompt = buildGemmaPrompt(messages)

        engine.generateResponseAsync(prompt) { partialResult, done ->
            if (partialResult.isNotEmpty()) {
                trySend(partialResult)
            }
            if (done) {
                close()
            }
        }

        // Keep the flow alive until the callbacks close it or the collector cancels.
        awaitClose()
    }.flowOn(Dispatchers.IO)

    /**
     * Single-turn text completion (non-chat).
     * Wraps the prompt in a minimal Gemma user turn.
     */
    suspend fun complete(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.8f,
    ): String = chat(
        messages = listOf(mapOf("role" to "user", "content" to prompt)),
        maxTokens = maxTokens,
        temperature = temperature,
    )

    fun completeStream(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.8f,
    ): Flow<String> = chatStream(
        messages = listOf(mapOf("role" to "user", "content" to prompt)),
        maxTokens = maxTokens,
        temperature = temperature,
    )

    // ── Prompt formatting ─────────────────────────────────────────────────────

    /**
     * Formats an OpenAI-style message list into a Gemma instruction prompt.
     *
     * System messages are prepended to the first user turn's content.
     * Assistant turns are replayed to give the model multi-turn context.
     * The prompt ends with "<start_of_turn>model\n" to trigger generation.
     */
    private fun buildGemmaPrompt(messages: List<Map<String, String>>): String {
        val sb = StringBuilder()

        // Collect system instructions to prepend to the first user message.
        val systemText = messages
            .filter { it["role"] == "system" }
            .joinToString("\n") { it["content"] ?: "" }
            .trim()

        var systemInjected = false

        for (msg in messages) {
            when (msg["role"]) {
                "system" -> continue // handled above
                "user" -> {
                    sb.append("<start_of_turn>user\n")
                    // Inject system instruction before first user message.
                    if (systemText.isNotEmpty() && !systemInjected) {
                        sb.append(systemText).append("\n\n")
                        systemInjected = true
                    }
                    sb.append(msg["content"] ?: "")
                    sb.append("<end_of_turn>\n")
                }
                "assistant" -> {
                    sb.append("<start_of_turn>model\n")
                    sb.append(msg["content"] ?: "")
                    sb.append("<end_of_turn>\n")
                }
            }
        }

        // Signal the model to generate the next turn.
        sb.append("<start_of_turn>model\n")
        return sb.toString()
    }
}

class InferenceException(message: String) : Exception(message)
