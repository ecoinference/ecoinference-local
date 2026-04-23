package com.gemma4.app1

import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Bridges Flutter ↔ Google AI Edge LLM Inference API.
 *
 * Channel: com.gemma4.app1/inference
 * Methods:
 *   loadModel(modelPath: String) → Boolean
 *   runInference(prompt: String, maxTokens: Int, temperature: Double) → String
 *   unloadModel() → void
 *   isModelLoaded() → Boolean
 */
class InferencePlugin(private val flutterEngine: FlutterEngine) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.gemma4.app1/inference"
    }

    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger, CHANNEL
    )
    private val scope = CoroutineScope(Dispatchers.Main)
    private var llmInference: LlmInference? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                    ?: return result.error("INVALID_ARG", "modelPath is required", null)
                loadModel(modelPath, result)
            }
            "runInference" -> {
                val prompt = call.argument<String>("prompt")
                    ?: return result.error("INVALID_ARG", "prompt is required", null)
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                val temperature = call.argument<Double>("temperature") ?: 0.8
                runInference(prompt, maxTokens, temperature, result)
            }
            "unloadModel" -> {
                unloadModel()
                result.success(null)
            }
            "isModelLoaded" -> result.success(llmInference != null)
            else -> result.notImplemented()
        }
    }

    private fun loadModel(modelPath: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    // Release any previously loaded model.
                    llmInference?.close()
                    llmInference = null

                    val options = LlmInferenceOptions.builder()
                        .setModelPath(modelPath)
                        // Use GPU delegate when available; fall back to CPU.
                        .setPreferredBackend(LlmInferenceOptions.Backend.GPU)
                        .build()
                    llmInference = LlmInference.createFromOptions(
                        flutterEngine.dartExecutor.binaryMessenger
                            .let {
                                // We need a Context — grab it from the application.
                                android.app.Application()
                            },
                        options
                    )
                }
                result.success(true)
            } catch (e: Exception) {
                result.error("LOAD_FAILED", e.message, null)
            }
        }
    }

    private fun runInference(
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        result: MethodChannel.Result
    ) {
        val engine = llmInference
        if (engine == null) {
            result.error("NOT_LOADED", "No model loaded", null)
            return
        }
        scope.launch {
            try {
                val output = withContext(Dispatchers.Default) {
                    engine.generateResponse(prompt)
                }
                result.success(output)
            } catch (e: Exception) {
                result.error("INFERENCE_FAILED", e.message, null)
            }
        }
    }

    private fun unloadModel() {
        llmInference?.close()
        llmInference = null
    }

    fun dispose() {
        unloadModel()
        channel.setMethodCallHandler(null)
    }
}
