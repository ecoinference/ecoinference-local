import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../constants/app_constants.dart';
import '../models/api_models.dart';
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

    // Resolve the path on disk.
    final settings = SettingsService.instance;
    settings.setSelectedModelId(modelId);

    return _json({'status': 'queued', 'model_id': modelId});
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

    final prompt = inference.buildChatPrompt(
      chatReq.messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
    );

    try {
      final output = await inference.runInference(
        prompt,
        maxTokens: chatReq.maxTokens,
        temperature: chatReq.temperature,
      );

      final response = ChatCompletionResponse(
        id: 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
        model: chatReq.model.isEmpty
            ? (inference.loadedModelId ?? 'gemma4')
            : chatReq.model,
        content: output,
        promptTokens: _estimateTokens(prompt),
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

    try {
      final output = await inference.runInference(
        compReq.prompt,
        maxTokens: compReq.maxTokens,
        temperature: compReq.temperature,
      );

      final response = CompletionResponse(
        id: 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
        model: compReq.model.isEmpty
            ? (inference.loadedModelId ?? 'gemma4')
            : compReq.model,
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

  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
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
