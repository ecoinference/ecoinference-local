package ai.ecoinference.app.inference

import android.content.Context
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
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
 * the `.litertlm` LiteRT Language Model bundle format used by Gemma 4.
 *
 * Conversation history is handled natively by [ConversationConfig.initialMessages]
 * rather than by building a raw Gemma prompt string — no manual turn formatting.
 *
 * Thread safety: [load] and [unload] must be called from a single coroutine;
 * [chat] / [chatStream] may be called concurrently (each creates its own
 * short-lived [com.google.ai.edge.litertlm.Conversation] instance).
 */
class LiteRtLmEngine(private val context: Context) {

    private var engine: Engine? = null
    private var _loadedModelId: String? = null
    private var _isMultimodal: Boolean = false

    val isLoaded: Boolean      get() = engine != null
    val loadedModelId: String? get() = _loadedModelId
    val isMultimodal: Boolean  get() = _isMultimodal

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
     *                     combined. The engine silently clamps to the model's limit.
     * @param multimodal   When true, initialises the vision backend (Backend.CPU)
     *                     and sets maxNumImages = 1 so the engine can accept image
     *                     input. Must match the model: setting this on a text-only
     *                     model will cause [Engine.initialize] to throw.
     */
    suspend fun load(
        modelId:      String,
        modelPath:    String,
        useGpu:       Boolean = false,
        maxNumTokens: Int     = 4096,
        multimodal:   Boolean = false,
    ) = withContext(Dispatchers.IO) {
        // Unload any previously loaded model first.
        unload()

        val file = File(modelPath)
        require(file.exists()) { "Model file not found: $modelPath" }
        require(file.length() > 1024 * 1024) {
            "Model file too small (${file.length()} bytes) — partial download?"
        }

        val engineConfig = EngineConfig(
            modelPath     = modelPath,
            backend       = if (useGpu) Backend.GPU() else Backend.CPU(),
            // Vision backend: must be set for models with a SigLIP encoder.
            // Leaving it null on a vision model causes a native crash at
            // inference time; setting it on a text-only model throws at
            // initialize() — so this must match the model's capabilities.
            visionBackend = if (multimodal) Backend.CPU() else null,
            // Sets the KV-cache size. The model binary is the hard ceiling;
            // the engine clamps silently if maxNumTokens exceeds it.
            maxNumTokens  = maxNumTokens,
            // Allow one image per turn when multimodal is enabled.
            maxNumImages  = if (multimodal) 1 else null,
            // Optional cache dir improves second-load latency.
            cacheDir      = context.cacheDir.path,
        )

        val newEngine = Engine(engineConfig)
        newEngine.initialize()
        engine         = newEngine
        _loadedModelId = modelId
        _isMultimodal  = multimodal
    }

    /** Closes the LiteRT-LM Engine and releases all native resources. */
    fun unload() {
        engine?.close()
        engine         = null
        _loadedModelId = null
        _isMultimodal  = false
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    /**
     * Generates a response for [messages] and returns the full text.
     *
     * Creates a short-lived Conversation, collects all tokens, closes it.
     * Call from Dispatchers.IO.
     */
    suspend fun chat(
        messages:    List<InferenceMessage>,
        maxTokens:   Int   = 2048,
        temperature: Float = 0.8f,
    ): String = withContext(Dispatchers.IO) {
        val eng = engine ?: throw InferenceException("No model loaded. Call load() first.")
        val parsed = parseMessages(messages)
        val config = buildConversationConfig(parsed.systemText, parsed.history, temperature, maxTokens)
        try {
            eng.createConversation(config).use { conversation ->
                val sb = StringBuilder()
                conversation.sendMessageAsync(parsed.lastUserContents).collect { message ->
                    sb.append(message.contents.toString())
                }
                sb.toString().removeGemmaStopTokens()
            }
        } finally {
            parsed.tempFiles.forEach { it.delete() }
        }
    }

    /**
     * Streaming variant of [chat]. Emits tokens as they are generated.
     * Multimodal messages (with [InferenceMessage.imageBytes]) are fully supported.
     */
    fun chatStream(
        messages:    List<InferenceMessage>,
        maxTokens:   Int   = 2048,
        temperature: Float = 0.8f,
    ): Flow<String> = flow {
        val eng = engine ?: throw InferenceException("No model loaded. Call load() first.")
        val parsed = parseMessages(messages)
        val config = buildConversationConfig(parsed.systemText, parsed.history, temperature, maxTokens)
        try {
            eng.createConversation(config).use { conversation ->
                conversation.sendMessageAsync(parsed.lastUserContents).collect { message ->
                    val token = message.contents.toString().removeGemmaStopTokens()
                    if (token.isNotEmpty()) emit(token)
                }
            }
        } finally {
            parsed.tempFiles.forEach { it.delete() }
        }
    }.flowOn(Dispatchers.IO)

    // ── Helpers ───────────────────────────────────────────────────────────────

    private data class ParsedMessages(
        val systemText:       String,
        val history:          List<Message>,
        val lastUserContents: Contents,
        val tempFiles:        List<File>,
    )

    /**
     * Splits an [InferenceMessage] list into system text, history turns,
     * and the final user [Contents] (text + optional image).
     *
     * When a message carries [InferenceMessage.imageBytes], the bytes are
     * written to a temp file and the LiteRT-LM representation is built as
     * `Contents.of(Content.ImageFile(path), Content.Text(…))`.
     * The LiteRT-LM engine requires a file path for image input — passing raw
     * bytes via Content.ImageBytes causes a native JNI crash.
     */
    private fun parseMessages(messages: List<InferenceMessage>): ParsedMessages {
        val systemText = messages
            .filter { it.role == "system" }
            .joinToString("\n") { it.text }
            .trim()

        val nonSystem = messages.filter { it.role != "system" }
        val lastMsg   = nonSystem.lastOrNull()
            ?: throw InferenceException("Message list contains no user message.")
        require(lastMsg.role == "user") {
            "Last message must have role 'user', got '${lastMsg.role}'."
        }

        val tempFiles = mutableListOf<File>()

        val historyMsgs = nonSystem.dropLast(1).mapNotNull { msg ->
            when (msg.role) {
                "user"      -> {
                    val (contents, tmp) = msg.toContentsWithFile()
                    if (tmp != null) tempFiles += tmp
                    Message.user(contents)
                }
                "assistant" -> Message.model(Contents.of(msg.text))
                else        -> null
            }
        }

        val (lastContents, lastTmp) = lastMsg.toContentsWithFile()
        if (lastTmp != null) tempFiles += lastTmp

        return ParsedMessages(
            systemText       = systemText,
            history          = historyMsgs,
            lastUserContents = lastContents,
            tempFiles        = tempFiles,
        )
    }

    /**
     * Converts an [InferenceMessage] to LiteRT-LM [Contents] + an optional
     * temp [File] that must be deleted after inference completes.
     *
     * When the message carries [imageBytes] the bytes are written to a temp
     * file in [Context.cacheDir] and the contents are built as:
     *   `Contents.of(Content.ImageFile(absolutePath), Content.Text(text))`
     *
     * Only passes image content when the engine was initialised with a vision
     * backend — passing Content.ImageFile to a text-only engine causes SIGSEGV.
     */
    private fun InferenceMessage.toContentsWithFile(): Pair<Contents, File?> {
        if (imageBytes != null && _isMultimodal) {
            val tmp = File(context.cacheDir, "img_${System.nanoTime()}.jpg")
            tmp.writeBytes(imageBytes)
            return Pair(
                Contents.of(Content.ImageFile(tmp.absolutePath), Content.Text(text)),
                tmp,
            )
        }
        return Pair(Contents.of(text), null)
    }

    // maxNumTokens is not a ConversationConfig constructor parameter in this
    // SDK version — output length is bounded by the EngineConfig.maxNumTokens
    // set at load time. The maxTokens arg is kept for API consistency.
    private fun buildConversationConfig(
        systemText: String,
        history:    List<Message>,
        temperature: Float,
        @Suppress("UNUSED_PARAMETER") maxTokens: Int = 2048,
    ): ConversationConfig = ConversationConfig(
        systemInstruction = if (systemText.isNotEmpty()) Contents.of(systemText) else null,
        initialMessages   = history,
        samplerConfig     = SamplerConfig(
            topK        = 40,
            topP        = 0.95,
            temperature = temperature.toDouble(),
        ),
    )
}

class InferenceException(message: String) : Exception(message)

// ── Stop-token stripping ──────────────────────────────────────────────────────

/**
 * Removes Gemma special stop tokens that the SDK may include in raw output.
 * Mirrors the iOS `removingGemmaStopTokens()` extension.
 */
private fun String.removeGemmaStopTokens(): String {
    var s = this
    for (token in listOf("<end_of_turn>", "<start_of_turn>", "<eos>", "</s>")) {
        s = s.replace(token, "")
    }
    return s
}
