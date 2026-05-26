package ai.ecoinference.app.inference

import android.content.Context
import kotlinx.coroutines.flow.Flow

/**
 * Singleton wrapper around [LiteRtLmEngine].
 * Mirrors the role of iOS InferenceService.swift.
 *
 * All mutating methods ([load], [unload]) must be called from a coroutine.
 * [chatStream] / [chat] may be called concurrently — each call creates its
 * own short-lived Conversation inside the engine.
 */
class InferenceService private constructor(context: Context) {

    companion object {
        @Volatile private var instance: InferenceService? = null

        fun getInstance(context: Context): InferenceService =
            instance ?: synchronized(this) {
                instance ?: InferenceService(context.applicationContext).also { instance = it }
            }
    }

    private val engine = LiteRtLmEngine(context)

    val isLoaded:      Boolean  get() = engine.isLoaded
    val loadedModelId: String?  get() = engine.loadedModelId
    val isMultimodal:  Boolean  get() = engine.isMultimodal

    suspend fun load(
        modelId:      String,
        modelPath:    String,
        useGpu:       Boolean = false,
        maxNumTokens: Int     = 4096,
        multimodal:   Boolean = false,
    ) = engine.load(
        modelId      = modelId,
        modelPath    = modelPath,
        useGpu       = useGpu,
        maxNumTokens = maxNumTokens,
        multimodal   = multimodal,
    )

    fun unload() = engine.unload()

    fun chatStream(
        messages:    List<InferenceMessage>,
        maxTokens:   Int   = 2048,
        temperature: Float = 0.8f,
    ): Flow<String> = engine.chatStream(messages, maxTokens, temperature)

    suspend fun chat(
        messages:    List<InferenceMessage>,
        maxTokens:   Int   = 2048,
        temperature: Float = 0.8f,
    ): String = engine.chat(messages, maxTokens, temperature)
}
