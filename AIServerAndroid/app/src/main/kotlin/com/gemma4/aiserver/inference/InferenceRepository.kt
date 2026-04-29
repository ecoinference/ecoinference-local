package com.gemma4.aiserver.inference

import android.content.Context
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.SamplerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Wraps the LiteRT-LM [Engine] API for on-device inference.
 *
 * Uses [com.google.ai.edge.litertlm:litertlm-android] which natively supports
 * the `.litertlm` LiteRT Language Model bundle format used by Gemma 4 and other
 * models on the LiteRT Community HuggingFace organisation.
 *
 * Conversation history is handled natively by [ConversationConfig.initialMessages]
 * rather than by building a raw Gemma prompt string — no manual turn formatting.
 *
 * Thread safety: [load] and [unload] must be called from a single coroutine;
 * [chat] / [chatStream] may be called concurrently (each creates its own
 * short-lived [com.google.ai.edge.litertlm.Conversation] instance).
 */
class InferenceRepository(private val context: Context) {

    private var engine: Engine? = null
    private var _loadedModelId: String? = null

    val isLoaded: Boolean get() = engine != null
    val loadedModelId: String? get() = _loadedModelId

    // ── Load / unload ─────────────────────────────────────────────────────────

    /**
     * Loads a model from [modelPath] on disk.
     *
     * Blocking — [Engine.initialize] maps the weight file into memory.
     * Call from a non-UI coroutine. The previous model is unloaded first.
     *
     * @param modelId      Catalogue ID — stored for status reporting.
     * @param modelPath    Absolute path to the .litertlm file.
     * @param useGpu       When true, requests the GPU backend (OpenCL/VNDK).
     *                     Falls back to CPU automatically when GPU is unavailable.
     * @param maxNumTokens Total KV-cache budget: prompt + history + response
     *                     combined. The .litertlm file for Gemma 4 E2B supports
     *                     up to 8 192 tokens; the SDK default is ~4 096. Set
     *                     this as high as the model supports and your RAM allows.
     *                     The engine silently clamps it to the model's hard limit.
     */
    suspend fun load(
        modelId: String,
        modelPath: String,
        useGpu: Boolean = false,
        maxNumTokens: Int = 8192,
    ) = withContext(Dispatchers.IO) {
        // Unload any previously loaded model first.
        unload()

        val file = File(modelPath)
        require(file.exists()) { "Model file not found: $modelPath" }
        require(file.length() > 1024 * 1024) {
            "Model file too small (${file.length()} bytes) — partial download?"
        }

        val engineConfig = EngineConfig(
            modelPath    = modelPath,
            backend      = if (useGpu) Backend.GPU() else Backend.CPU(),
            // Sets the KV-cache size.  The model binary is the hard ceiling;
            // the engine clamps silently if maxNumTokens exceeds it.
            maxNumTokens = maxNumTokens,
            // Optional cache dir improves second-load latency.
            cacheDir     = context.cacheDir.path,
        )

        val newEngine = Engine(engineConfig)
        newEngine.initialize()
        engine = newEngine
        _loadedModelId = modelId
    }

    /** Closes the LiteRT-LM Engine and releases all native resources. */
    fun unload() {
        engine?.close()
        engine = null
        _loadedModelId = null
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    /**
     * Generates a response for [messages] and returns the full text.
     *
     * Creates a short-lived Conversation, collects all tokens, closes it.
     * Call from Dispatchers.IO.
     *
     * @param maxTokens Maximum tokens to generate in this response.
     *                  Must be less than the engine's [maxNumTokens] minus the
     *                  prompt length.  Default 2 048 suits most interactions.
     */
    suspend fun chat(
        messages: List<Map<String, String>>,
        maxTokens: Int = 2048,
        temperature: Float = 0.8f,
    ): String = withContext(Dispatchers.IO) {
        val eng = engine
            ?: throw InferenceException("No model loaded. Call load() first.")

        val (systemText, history, lastUserMessage) = parseMessages(messages)
        val config = buildConversationConfig(systemText, history, temperature, maxTokens)

        eng.createConversation(config).use { conversation ->
            val sb = StringBuilder()
            conversation.sendMessageAsync(lastUserMessage).collect { message ->
                sb.append(message.contents.toString())
            }
            sb.toString()
        }
    }

    /**
     * Streaming variant of [chat].
     *
     * Emits tokens as they are generated. The underlying [Engine.createConversation]
     * call is wrapped in a [flow] so coroutine cancellation propagates correctly.
     */
    fun chatStream(
        messages: List<Map<String, String>>,
        maxTokens: Int = 2048,
        temperature: Float = 0.8f,
    ): Flow<String> = flow {
        val eng = engine
            ?: throw InferenceException("No model loaded. Call load() first.")

        val (systemText, history, lastUserMessage) = parseMessages(messages)
        val config = buildConversationConfig(systemText, history, temperature, maxTokens)

        eng.createConversation(config).use { conversation ->
            conversation.sendMessageAsync(lastUserMessage).collect { message ->
                emit(message.contents.toString())
            }
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Single-turn text completion (non-chat).
     * Wraps the prompt in a minimal user turn.
     */
    suspend fun complete(
        prompt: String,
        maxTokens: Int = 2048,
        temperature: Float = 0.8f,
    ): String = chat(
        messages = listOf(mapOf("role" to "user", "content" to prompt)),
        maxTokens = maxTokens,
        temperature = temperature,
    )

    fun completeStream(
        prompt: String,
        maxTokens: Int = 2048,
        temperature: Float = 0.8f,
    ): Flow<String> = chatStream(
        messages = listOf(mapOf("role" to "user", "content" to prompt)),
        maxTokens = maxTokens,
        temperature = temperature,
    )

    // ── Helpers ───────────────────────────────────────────────────────────────

    private data class ParsedMessages(
        val systemText: String,
        val history: List<Message>,
        val lastUserMessage: String,
    )

    /**
     * Splits an OpenAI-style message list into:
     * - [systemText]: concatenated system message content (if any)
     * - [history]: prior user/assistant turns as [Message] objects
     * - [lastUserMessage]: the final user message to send
     *
     * The last message in [messages] must have role "user".
     */
    private fun parseMessages(messages: List<Map<String, String>>): ParsedMessages {
        val systemText = messages
            .filter { it["role"] == "system" }
            .joinToString("\n") { it["content"] ?: "" }
            .trim()

        val nonSystem = messages.filter { it["role"] != "system" }

        val lastMsg = nonSystem.lastOrNull()
            ?: throw InferenceException("Message list contains no user message.")
        require(lastMsg["role"] == "user") {
            "Last message must have role 'user', got '${lastMsg["role"]}'."
        }

        val historyMsgs = nonSystem.dropLast(1).mapNotNull { msg ->
            when (msg["role"]) {
                "user"      -> Message.user(msg["content"] ?: "")
                "assistant" -> Message.model(Contents.of(msg["content"] ?: ""))
                else        -> null
            }
        }

        return ParsedMessages(
            systemText = systemText,
            history    = historyMsgs,
            lastUserMessage = lastMsg["content"] ?: "",
        )
    }

    // maxNumTokens is not a ConversationConfig constructor parameter in this
    // SDK version — output length is bounded by the EngineConfig.maxNumTokens
    // set at load time (8192). The unused maxTokens call-site arg is kept for
    // API consistency but has no effect here.
    private fun buildConversationConfig(
        systemText: String,
        history: List<Message>,
        temperature: Float,
        @Suppress("UNUSED_PARAMETER") maxTokens: Int = 2048,
    ): ConversationConfig = ConversationConfig(
        systemInstruction = if (systemText.isNotEmpty()) Contents.of(systemText) else null,
        initialMessages   = history,
        samplerConfig     = SamplerConfig(topK = 40, topP = 0.95, temperature = temperature.toDouble()),
    )
}

class InferenceException(message: String) : Exception(message)
