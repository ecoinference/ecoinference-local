import 'package:flutter_gemma/flutter_gemma.dart';

/// Wraps the flutter_gemma plugin for on-device Gemma inference.
/// No native bridge code required — flutter_gemma handles iOS and Android
/// internally via Google AI Edge (MediaPipe Tasks GenAI).
class InferenceService {
  InferenceService._();
  static final InferenceService instance = InferenceService._();

  bool _modelLoaded = false;
  String? _loadedModelId;

  bool get modelLoaded => _modelLoaded;
  String? get loadedModelId => _loadedModelId;

  /// Loads a Gemma .bin model from [modelPath] on disk.
  Future<bool> loadModel(String modelPath, String modelId) async {
    try {
      await FlutterGemmaPlugin.instance.init(
        modelPath: modelPath,
        temperature: 0.8,
        topK: 40,
        randomSeed: 1,
        maxTokens: 1024,
      );
      _modelLoaded = true;
      _loadedModelId = modelId;
      return true;
    } catch (e) {
      _modelLoaded = false;
      throw InferenceException('loadModel failed: $e');
    }
  }

  /// Runs a single blocking inference call with [prompt].
  Future<String> runInference(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.8,
  }) async {
    if (!_modelLoaded) {
      throw InferenceException('No model loaded. Call loadModel() first.');
    }
    try {
      final response =
          await FlutterGemmaPlugin.instance.getResponse(prompt: prompt);
      return response ?? '';
    } catch (e) {
      throw InferenceException('runInference failed: $e');
    }
  }

  /// Converts a list of chat messages into Gemma's instruction-tuned prompt
  /// format:
  ///   <start_of_turn>user\n{text}<end_of_turn>\n<start_of_turn>model
  String buildChatPrompt(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      if (role == 'system') {
        buf.write('<start_of_turn>user\n[System: $content]<end_of_turn>\n');
      } else {
        final gemmaRole = role == 'assistant' ? 'model' : 'user';
        buf.write('<start_of_turn>$gemmaRole\n$content<end_of_turn>\n');
      }
    }
    buf.write('<start_of_turn>model\n');
    return buf.toString();
  }

  Future<void> unloadModel() async {
    try {
      // flutter_gemma does not expose an explicit unload; reinitialising
      // with a new model path replaces the current one.
    } catch (_) {}
    _modelLoaded = false;
    _loadedModelId = null;
  }
}

class InferenceException implements Exception {
  const InferenceException(this.message);
  final String message;
  @override
  String toString() => 'InferenceException: $message';
}
