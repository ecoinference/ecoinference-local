import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Wraps flutter_gemma 0.13.x for on-device Gemma inference.
///
/// Uses the modern InferenceChat API:
///   FlutterGemma.initialize()           — called once in main()
///   FlutterGemma.installModel()…        — registers model file
///   FlutterGemma.getActiveModel()       — returns InferenceModel
///   model.createChat()                  — creates InferenceChat (handles
///                                         history, thinking filter, fileType)
///   chat.addQueryChunk(Message)         — add each turn
///   chat.generateChatResponse()         — blocking response → ModelResponse
///
/// iOS compatibility note:
///   Gemma 4 (.litertlm) crashes at inference on iOS with MediaPipe 0.10.33.
///   Use .task models (Gemma 3n, Gemma 3) for iOS.
///   .litertlm with ModelFileType.litertlm is reserved for Android/Desktop.
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

    // Detect file type from extension so the correct engine is selected.
    final fileType = cleanPath.endsWith('.litertlm')
        ? ModelFileType.litertlm
        : ModelFileType.task;

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: fileType,
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

  /// Runs inference over a list of chat messages using the InferenceChat API.
  ///
  /// [messages] follows the OpenAI format: each map has 'role' (system /
  /// user / assistant) and 'content'. System messages are extracted and
  /// passed as [systemInstruction] to the chat session; user and assistant
  /// turns are replayed in order to rebuild multi-turn context.
  ///
  /// Returns the assistant's reply as a plain string (thinking tokens are
  /// automatically stripped by [generateChatResponse]).
  Future<String> runChatInference(
    List<Map<String, String>> messages, {
    int maxTokens = 512,
    double temperature = 0.8,
  }) async {
    if (!_modelLoaded) {
      throw InferenceException('No model loaded. Call loadModel() first.');
    }
    try {
      // Collect system instruction(s) to pass natively where supported.
      final systemInstruction = messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'] ?? '')
          .join('\n')
          .trim();

      final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);

      final chat = await model.createChat(
        temperature: temperature,
        systemInstruction: systemInstruction.isEmpty ? null : systemInstruction,
      );

      // Replay all non-system turns to rebuild conversation context.
      for (final msg in messages.where((m) => m['role'] != 'system')) {
        final isUser = (msg['role'] ?? 'user') == 'user';
        await chat.addQueryChunk(
          Message.text(text: msg['content'] ?? '', isUser: isUser),
        );
      }

      final response = await chat.generateChatResponse();
      await model.close();

      // Extract text from the typed response.
      return switch (response) {
        TextResponse r     => r.token,
        ThinkingResponse r => r.content,
        _                  => '',
      };
    } catch (e) {
      throw InferenceException('runChatInference failed: $e');
    }
  }

  /// Convenience wrapper for single-prompt (non-chat) inference.
  /// Used by the /v1/completions endpoint.
  Future<String> runInference(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.8,
  }) =>
      runChatInference(
        [{'role': 'user', 'content': prompt}],
        maxTokens: maxTokens,
        temperature: temperature,
      );

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
