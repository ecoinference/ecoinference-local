import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Wraps flutter_gemma 0.13.x for on-device Gemma inference.
///
/// New API (since v0.5.0 / v0.11.10):
///   FlutterGemma.initialize()           — called once in main()
///   FlutterGemma.installModel().fromFile().install()  — registers model
///   FlutterGemma.getActiveModel()       — returns InferenceModel
///   model.createSession()               — per-request session
///   session.addQueryChunk(Message)      — add prompt
///   session.getResponse()               — blocking response
class InferenceService {
  InferenceService._();
  static final InferenceService instance = InferenceService._();

  bool _modelLoaded = false;
  String? _loadedModelId;

  bool get modelLoaded => _modelLoaded;
  String? get loadedModelId => _loadedModelId;

  /// Registers a model file with flutter_gemma.
  /// Automatically detects .litertlm vs .task from the file extension.
  Future<bool> loadModel(String modelPath, String modelId) async {
    // ── Pre-flight checks ──────────────────────────────────────────────────
    final file = File(modelPath);
    if (!file.existsSync()) {
      throw InferenceException(
          'Model file not found at:\n$modelPath\n\nTry re-downloading.');
    }
    final sizeBytes = file.lengthSync();
    if (sizeBytes < 1024 * 1024) {
      throw InferenceException(
          'Model file too small (${(sizeBytes / 1024).toStringAsFixed(1)} KB). '
          'Partial download — delete and re-download.');
    }

    // Strip any file:// prefix — MediaPipe needs a bare POSIX path.
    final cleanPath = modelPath.startsWith('file://')
        ? Uri.parse(modelPath).toFilePath()
        : modelPath;

    // Detect file type from extension so MediaPipe parses it correctly.
    final fileType = cleanPath.endsWith('.litertlm')
        ? ModelFileType.litertlm
        : ModelFileType.task;

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        modelFileType: fileType,
      ).fromFile(cleanPath).install();

      _modelLoaded = true;
      _loadedModelId = modelId;
      return true;
    } catch (e) {
      _modelLoaded = false;
      throw InferenceException(
          'loadModel failed.\n'
          'Path: $cleanPath\n'
          'Size: ${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB\n'
          'Error: $e');
    }
  }

  /// Runs a single blocking inference call and returns the response string.
  Future<String> runInference(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.8,
  }) async {
    if (!_modelLoaded) {
      throw InferenceException('No model loaded. Call loadModel() first.');
    }
    try {
      final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
      final session = await model.createSession();
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await session.getResponse();
      await session.close();
      await model.close();
      return response ?? '';
    } catch (e) {
      throw InferenceException('runInference failed: $e');
    }
  }

  /// Formats chat messages into a single prompt string for the model.
  /// For the new API each call is treated as a standalone turn, so we
  /// flatten the history into one user message here.
  String buildChatPrompt(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      switch (role) {
        case 'system':
          buf.writeln('[System: $content]\n');
        case 'assistant':
          buf.writeln('Assistant: $content\n');
        default:
          buf.writeln('User: $content\n');
      }
    }
    return buf.toString().trim();
  }

  Future<void> unloadModel() async {
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
