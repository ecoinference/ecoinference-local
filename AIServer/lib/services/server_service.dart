import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../constants/app_constants.dart';
import '../constants/model_catalog.dart';
import '../models/api_models.dart';
import '../services/download_service.dart';
import '../services/inference_service.dart';
import '../services/settings_service.dart';

/// Manages the embedded shelf HTTP server.
/// Exposes an OpenAI-compatible REST API on localhost.
class ServerService {
  ServerService._();
  static final ServerService instance = ServerService._();

  HttpServer? _server;
  bool get isRunning => _server != null;
  int get port => SettingsService.instance.port;

  /// Starts the server. Throws [ServerException] on failure.
  Future<void> start() async {
    if (_server != null) return; // already running

    final router = Router()
      ..get(AppConstants.routeHealth, _healthHandler)
      ..get(AppConstants.routeModels, _modelsHandler)
      ..post(AppConstants.routeLoadModel, _loadModelHandler)
      ..post(AppConstants.routeChatCompletions, _chatCompletionsHandler)
      ..post(AppConstants.routeCompletions, _completionsHandler);

    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(logRequests())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        port,
      );
      _server!.autoCompress = true;
    } catch (e) {
      throw ServerException('Failed to bind on port $port: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  Response _healthHandler(Request req) {
    final inference = InferenceService.instance;
    return _json({
      'status': 'ok',
      'model_loaded': inference.modelLoaded,
      'model_id': inference.loadedModelId,
      'port': port,
    });
  }

  Response _modelsHandler(Request req) {
    final inference = InferenceService.instance;
    return _json({
      'object': 'list',
      'data': inference.loadedModelId != null
          ? [
              {
                'id': inference.loadedModelId,
                'object': 'model',
                'owned_by': 'google',
              }
            ]
          : [],
    });
  }

  Future<Response> _loadModelHandler(Request req) async {
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON');

    final modelId = body['model_id'] as String?;
    if (modelId == null || modelId.isEmpty) {
      return _badRequest('model_id is required');
    }

    // Validate against the catalog so we can resolve a file path.
    final model = ModelCatalog.findById(modelId);
    if (model == null) {
      final available = ModelCatalog.models.map((m) => m.id).join(', ');
      return _badRequest(
          'Unknown model_id "$modelId". Available: $available');
    }

    final modelPath = await DownloadService.instance.modelFilePath(model);
    if (!await _fileExists(modelPath)) {
      return Response(
        404,
        body: jsonEncode({
          'error': 'Model file not found on device. '
              'Download the model first via the app.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Persist the selection then hot-swap the running model.
    await SettingsService.instance.setSelectedModelId(modelId);

    final inference = InferenceService.instance;

    // Unload whatever is currently active so the new load starts clean.
    if (inference.modelLoaded) {
      await inference.unloadModel();
    }

    try {
      await inference.loadModel(modelPath, modelId);
      return _json({
        'status': 'loaded',
        'model_id': modelId,
        'model': {
          'id': modelId,
          'object': 'model',
          'owned_by': 'google',
        },
      });
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _chatCompletionsHandler(Request req) async {
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON');

    final inference = InferenceService.instance;
    if (!inference.modelLoaded) {
      return Response(
        503,
        body: jsonEncode({'error': 'No model loaded'}),
        headers: {'content-type': 'application/json'},
      );
    }

    late ChatCompletionRequest chatReq;
    try {
      chatReq = ChatCompletionRequest.fromJson(body);
    } catch (e) {
      return _badRequest('Malformed request: $e');
    }

    final messages = chatReq.messages
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final modelName = chatReq.model.isEmpty
        ? (inference.loadedModelId ?? 'gemma')
        : chatReq.model;

    // ── Streaming (SSE) path ────────────────────────────────────────────────
    if (chatReq.stream) {
      final id = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
      final tokenStream = inference.runChatInferenceStream(
        messages,
        maxTokens: chatReq.maxTokens,
        temperature: chatReq.temperature,
      );
      return Response.ok(
        _chatSseBytes(tokenStream, id: id, model: modelName),
        headers: {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          'x-accel-buffering': 'no', // hint to proxies/nginx to disable buffering
        },
      );
    }

    // ── Non-streaming path ──────────────────────────────────────────────────
    try {
      final output = await inference.runChatInference(
        messages,
        maxTokens: chatReq.maxTokens,
        temperature: chatReq.temperature,
      );

      final inputText = chatReq.messages.map((m) => m.content).join(' ');
      final response = ChatCompletionResponse(
        id: 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
        model: modelName,
        content: output,
        promptTokens: _estimateTokens(inputText),
        completionTokens: _estimateTokens(output),
      );
      return _json(response.toJson());
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _completionsHandler(Request req) async {
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON');

    final inference = InferenceService.instance;
    if (!inference.modelLoaded) {
      return Response(
        503,
        body: jsonEncode({'error': 'No model loaded'}),
        headers: {'content-type': 'application/json'},
      );
    }

    late CompletionRequest compReq;
    try {
      compReq = CompletionRequest.fromJson(body);
    } catch (e) {
      return _badRequest('Malformed request: $e');
    }

    final modelName = compReq.model.isEmpty
        ? (inference.loadedModelId ?? 'gemma')
        : compReq.model;

    // ── Streaming (SSE) path ────────────────────────────────────────────────
    if (compReq.stream) {
      final id = 'cmpl-${DateTime.now().millisecondsSinceEpoch}';
      final tokenStream = inference.runChatInferenceStream(
        [{'role': 'user', 'content': compReq.prompt}],
        maxTokens: compReq.maxTokens,
        temperature: compReq.temperature,
      );
      return Response.ok(
        _completionSseBytes(tokenStream, id: id, model: modelName),
        headers: {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          'x-accel-buffering': 'no',
        },
      );
    }

    // ── Non-streaming path ──────────────────────────────────────────────────
    try {
      final output = await inference.runInference(
        compReq.prompt,
        maxTokens: compReq.maxTokens,
        temperature: compReq.temperature,
      );

      final response = CompletionResponse(
        id: 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
        model: modelName,
        text: output,
      );
      return _json(response.toJson());
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Response _json(Map<String, dynamic> data, {int status = 200}) => Response(
        status,
        body: jsonEncode(data),
        headers: {'content-type': 'application/json'},
      );

  Response _badRequest(String message) => Response(
        400,
        body: jsonEncode({'error': message}),
        headers: {'content-type': 'application/json'},
      );

  Future<Map<String, dynamic>?> _parseBody(Request req) async {
    try {
      final raw = await req.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Rough token estimate: ~4 chars per token.
  int _estimateTokens(String text) => (text.length / 4).ceil();

  Future<bool> _fileExists(String path) async =>
      File(path).exists();

  // ── SSE helpers ───────────────────────────────────────────────────────────

  /// Wraps a token [Stream<String>] as an SSE byte stream in the
  /// OpenAI `chat.completion.chunk` format.
  ///
  /// Format per chunk:
  /// ```
  /// data: {"id":"...","object":"chat.completion.chunk",...}\n\n
  /// ```
  /// Terminated with:
  /// ```
  /// data: [DONE]\n\n
  /// ```
  Stream<List<int>> _chatSseBytes(
    Stream<String> tokens, {
    required String id,
    required String model,
  }) async* {
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // First chunk signals the assistant role.
    yield _sseEncode({
      'id': id,
      'object': 'chat.completion.chunk',
      'created': created,
      'model': model,
      'choices': [
        {'index': 0, 'delta': {'role': 'assistant', 'content': ''}, 'finish_reason': null}
      ],
    });

    await for (final token in tokens) {
      yield _sseEncode({
        'id': id,
        'object': 'chat.completion.chunk',
        'created': created,
        'model': model,
        'choices': [
          {'index': 0, 'delta': {'content': token}, 'finish_reason': null}
        ],
      });
    }

    // Final chunk with finish_reason.
    yield _sseEncode({
      'id': id,
      'object': 'chat.completion.chunk',
      'created': created,
      'model': model,
      'choices': [
        {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': 'stop'}
      ],
    });

    yield utf8.encode('data: [DONE]\n\n');
  }

  /// Wraps a token [Stream<String>] as an SSE byte stream in the
  /// OpenAI `text_completion` chunk format (used by /v1/completions).
  Stream<List<int>> _completionSseBytes(
    Stream<String> tokens, {
    required String id,
    required String model,
  }) async* {
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await for (final token in tokens) {
      yield _sseEncode({
        'id': id,
        'object': 'text_completion',
        'created': created,
        'model': model,
        'choices': [
          {'text': token, 'index': 0, 'finish_reason': null}
        ],
      });
    }

    yield _sseEncode({
      'id': id,
      'object': 'text_completion',
      'created': created,
      'model': model,
      'choices': [
        {'text': '', 'index': 0, 'finish_reason': 'stop'}
      ],
    });

    yield utf8.encode('data: [DONE]\n\n');
  }

  /// Encodes [data] as a single SSE `data:` line followed by two newlines.
  List<int> _sseEncode(Map<String, dynamic> data) =>
      utf8.encode('data: ${jsonEncode(data)}\n\n');

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  // Restrict to localhost — the server only binds on loopback so only
  // localhost origins are valid. Wildcard '*' would allow any webpage
  // the user visits to make inference requests to the local server.
  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': 'http://localhost',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
}

class ServerException implements Exception {
  const ServerException(this.message);
  final String message;
  @override
  String toString() => 'ServerException: $message';
}
