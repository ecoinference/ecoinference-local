import Flutter
import MediaPipeTasksGenAI
import MediaPipeTasksGenAIIOS

/**
 Bridges Flutter ↔ Google AI Edge LLM Inference API on iOS.

 Channel: com.gemma4.app1/inference
 Methods:
   loadModel(modelPath: String) → Bool
   runInference(prompt: String, maxTokens: Int, temperature: Double) → String
   unloadModel() → void
   isModelLoaded() → Bool
 */
class InferencePlugin: NSObject, FlutterPlugin {

    static let channelName = "com.gemma4.app1/inference"

    private var llmInference: LlmInference?
    private let queue = DispatchQueue(label: "com.gemma4.inference", qos: .userInitiated)

    // MARK: – Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = InferencePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: – Method call handler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let modelPath = args["modelPath"] as? String
            else {
                result(FlutterError(code: "INVALID_ARG",
                                    message: "modelPath is required",
                                    details: nil))
                return
            }
            loadModel(path: modelPath, result: result)

        case "runInference":
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String
            else {
                result(FlutterError(code: "INVALID_ARG",
                                    message: "prompt is required",
                                    details: nil))
                return
            }
            let maxTokens  = args["maxTokens"]  as? Int    ?? 512
            let temperature = args["temperature"] as? Double ?? 0.8
            runInference(prompt: prompt,
                         maxTokens: maxTokens,
                         temperature: temperature,
                         result: result)

        case "unloadModel":
            unloadModel()
            result(nil)

        case "isModelLoaded":
            result(llmInference != nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: – Private helpers

    private func loadModel(path: String, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                self.llmInference = nil // release previous
                let options = LlmInference.Options(modelPath: path)
                options.maxTokens = 1024
                // Prefer GPU delegate; falls back to CPU automatically.
                self.llmInference = try LlmInference(options: options)
                DispatchQueue.main.async { result(true) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "LOAD_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    private func runInference(prompt: String,
                               maxTokens: Int,
                               temperature: Double,
                               result: @escaping FlutterResult) {
        guard let engine = llmInference else {
            result(FlutterError(code: "NOT_LOADED",
                                message: "No model loaded",
                                details: nil))
            return
        }
        queue.async {
            do {
                let output = try engine.generateResponse(inputText: prompt)
                DispatchQueue.main.async { result(output) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INFERENCE_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    private func unloadModel() {
        llmInference = nil
    }
}
