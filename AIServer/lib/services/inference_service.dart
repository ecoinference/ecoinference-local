import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'settings_service.dart';

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
  String? _loadedFileName; // basename flutter_gemma uses as its model key

  bool get modelLoaded => _modelLoaded;
  String? get loadedModelId => _loadedModelId;

  /// Returns the preferred backend based on the current settings.
  /// null = let flutter_gemma / MediaPipe auto-select (default).
  PreferredBackend? get _preferredBackend =>
      SettingsService.instance.useGpu ? PreferredBackend.gpu : null;

  /// Registers a model file with flutter_gemma, then warms up the engine.
  ///
  /// Two-phase load:
  ///   Phase 1 (0 → 50 %)  — `installModel().fromFile().withProgress()` registers
  ///     the file path in flutter_gemma's metadata store.  For a local file this
  ///     is near-instant, but the progress hook is in place for future network or
  ///     bundled sources that may take longer.
  ///   Phase 2 (50 → 100 %) — `getActiveModel()` triggers the native engine
  ///     (MediaPipe / LiteRT) to memory-map the weight file and initialise the
  ///     runtime.  The resulting model is closed immediately; the OS page-cache
  ///     keeps the weights hot so every subsequent [runChatInference] call is fast.
  ///
  /// [onProgress] receives integer values 0-100 as the load advances.
  Future<bool> loadModel(
    String modelPath,
    String modelId, {
    void Function(int progress)? onProgress,
  }) async {
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
      // ── Phase 1: register file path (0 → 50 %) ──────────────────────────
      onProgress?.call(0);
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: fileType,
      )
          .fromFile(cleanPath)
          .withProgress((p) => onProgress?.call((p * 0.5).round()))
          .install();
      onProgress?.call(50);

      // ── Phase 2: warm-up engine (50 → 100 %) ────────────────────────────
      // Creates a native LlmInference / LiteRT session, which maps the weight
      // file into memory.  We close it immediately; subsequent calls to
      // getActiveModel() in runChatInference() reuse the warm page-cache.
      final warmUp = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: _preferredBackend,
      );
      await warmUp.close();
      onProgress?.call(100);

      _modelLoaded = true;
      _loadedModelId = modelId;
      _loadedFileName = cleanPath.split('/').last;
      return true;
    } catch (e) {
      _modelLoaded = false;
      _loadedModelId = null;
      _loadedFileName = null;
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
      throw const InferenceException('No model loaded. Call loadModel() first.');
    }
    try {
      // Collect system instruction(s) to pass natively where supported.
      final systemInstruction = messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'] ?? '')
          .join('\n')
          .trim();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: _preferredBackend,
      );

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

  /// Streaming variant of [runChatInference].
  ///
  /// Yields one decoded token string at a time using the
  /// [InferenceChat.generateChatResponseAsync] stream.  Thinking tokens
  /// ([ThinkingResponse]) are silently dropped so only visible assistant text
  /// reaches the caller.  The underlying [InferenceModel] is closed in a
  /// `finally` block, so it is released even if the consumer cancels early.
  ///
  /// Used by the `/v1/chat/completions` and `/v1/completions` SSE paths.
  Stream<String> runChatInferenceStream(
    List<Map<String, String>> messages, {
    int maxTokens = 512,
    double temperature = 0.8,
  }) async* {
    if (!_modelLoaded) {
      throw const InferenceException('No model loaded. Call loadModel() first.');
    }

    InferenceModel? model;
    try {
      final systemInstruction = messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'] ?? '')
          .join('\n')
          .trim();

      model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: _preferredBackend,
      );

      final chat = await model.createChat(
        temperature: temperature,
        systemInstruction: systemInstruction.isEmpty ? null : systemInstruction,
      );

      for (final msg in messages.where((m) => m['role'] != 'system')) {
        final isUser = (msg['role'] ?? 'user') == 'user';
        await chat.addQueryChunk(
          Message.text(text: msg['content'] ?? '', isUser: isUser),
        );
      }

      await for (final response in chat.generateChatResponseAsync()) {
        final token = switch (response) {
          TextResponse r     => r.token,
          ThinkingResponse _ => '', // thinking tokens not exposed in stream
          _                  => '',
        };
        if (token.isNotEmpty) yield token;
      }
    } catch (e) {
      throw InferenceException('runChatInferenceStream failed: $e');
    } finally {
      await model?.close();
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

  /// Unloads the current model from both Dart state and flutter_gemma's
  /// metadata store.  Because the model was installed via [fromFile] the
  /// weight file itself is protected and is never deleted — only the
  /// registration entry is removed, giving the next [loadModel] call a
  /// clean slate to re-register and re-warm-up.
  Future<void> unloadModel() async {
    final fileName = _loadedFileName;
    _modelLoaded = false;
    _loadedModelId = null;
    _loadedFileName = null;

    if (fileName != null) {
      try {
        await FlutterGemma.uninstallModel(fileName);
      } catch (_) {
        // Best-effort: if the entry was already gone, ignore the error.
      }
    }
  }
}

class InferenceException implements Exception {
  const InferenceException(this.message);
  final String message;
  @override
  String toString() => 'InferenceException: $message';
}
