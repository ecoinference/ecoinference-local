import 'dart:convert';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';

/// Communicates with the native inference bridge via a MethodChannel.
/// The native side (Kotlin / Swift) wraps Google AI Edge LLM Inference API.
class InferenceService {
  InferenceService._();
  static final InferenceService instance = InferenceService._();

  static const MethodChannel _channel =
      MethodChannel(AppConstants.inferenceChannel);

  bool _modelLoaded = false;
  String? _loadedModelId;

  bool get modelLoaded => _modelLoaded;
  String? get loadedModelId => _loadedModelId;

  /// Loads a .task model file from [modelPath] on disk.
  /// Returns true on success.
  Future<bool> loadModel(String modelPath, String modelId) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        AppConstants.methodLoadModel,
        {'modelPath': modelPath},
      );
      _modelLoaded = result ?? false;
      if (_modelLoaded) _loadedModelId = modelId;
      return _modelLoaded;
    } on PlatformException catch (e) {
      _modelLoaded = false;
      throw InferenceException('loadModel failed: ${e.message}');
    }
  }

  /// Runs inference for a single prompt string.
  /// [maxTokens] and [temperature] are passed to the native side.
  Future<String> runInference(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.8,
  }) async {
    if (!_modelLoaded) {
      throw InferenceException('No model loaded. Call loadModel() first.');
    }
    try {
      final result = await _channel.invokeMethod<String>(
        AppConstants.methodRunInference,
        {
          'prompt': prompt,
          'maxTokens': maxTokens,
          'temperature': temperature,
        },
      );
      return result ?? '';
    } on PlatformException catch (e) {
      throw InferenceException('runInference failed: ${e.message}');
    }
  }

  /// Converts a list of chat messages to a single prompt string using
  /// Gemma's instruction-tuned format:
  ///   <start_of_turn>user\n{text}<end_of_turn>\n<start_of_turn>model
  String buildChatPrompt(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      if (role == 'system') {
        // Prepend system message as a user turn so Gemma honours it.
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
      await _channel.invokeMethod(AppConstants.methodUnloadModel);
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
