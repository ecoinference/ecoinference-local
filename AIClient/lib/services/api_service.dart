import 'dart:convert';

import 'package:dio/dio.dart';
import '../models/chat_message.dart';
import '../models/server_config.dart';

/// REST client for the AIServer inference server.
/// All methods throw [ApiException] on failure.
class ApiService {
  ApiService(this.config)
      : _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: const Duration(seconds: 5),
          // Long receive timeout for inference (up to 3 min for large models).
          receiveTimeout: const Duration(minutes: 3),
          headers: {'Content-Type': 'application/json'},
        ));

  final ServerConfig config;
  final Dio _dio;

  // ── Health ──────────────────────────────────────────────────────────────────

  /// Returns true if AIServer is reachable and a model is loaded.
  Future<HealthStatus> checkHealth() async {
    try {
      final res = await _dio.get('/health');
      return HealthStatus(
        ok: true,
        modelLoaded: res.data['model_loaded'] as bool? ?? false,
        modelId: res.data['model_id'] as String?,
        port: res.data['port'] as int? ?? config.port,
      );
    } on DioException catch (e) {
      return HealthStatus(ok: false, modelLoaded: false, error: _msg(e));
    }
  }

  // ── Chat completions ────────────────────────────────────────────────────────

  /// Sends [messages] and returns the full assistant reply as a single string.
  Future<String> chatCompletion({
    required List<ChatMessage> messages,
    int maxTokens = 512,
    double temperature = 0.8,
  }) async {
    try {
      final res = await _dio.post(
        '/v1/chat/completions',
        data: {
          'model': config.modelId,
          'messages': messages.map((m) => m.toApiJson()).toList(),
          'max_tokens': maxTokens,
          'temperature': temperature,
        },
      );
      final choices = res.data['choices'] as List;
      if (choices.isEmpty) throw const ApiException('Empty choices in response');
      return choices.first['message']['content'] as String;
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  /// Streams the assistant reply token-by-token via SSE (`stream: true`).
  ///
  /// Yields each non-empty content token as it arrives. Throws [ApiException]
  /// if the connection fails before the stream starts.
  Stream<String> chatCompletionStream({
    required List<ChatMessage> messages,
    int maxTokens = 512,
    double temperature = 0.8,
  }) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/v1/chat/completions',
        data: {
          'model': config.modelId,
          'messages': messages.map((m) => m.toApiJson()).toList(),
          'max_tokens': maxTokens,
          'temperature': temperature,
          'stream': true,
        },
        options: Options(responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }

    var buffer = '';
    await for (final chunk in response.data!.stream) {
      buffer += utf8.decode(chunk);
      // Split on newlines; keep any trailing incomplete line in the buffer.
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') return;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices.first['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } catch (_) {
          // Skip malformed / partial JSON chunks.
        }
      }
    }
  }

  // ── Text completions ────────────────────────────────────────────────────────

  Future<String> completion({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.8,
  }) async {
    try {
      final res = await _dio.post(
        '/v1/completions',
        data: {
          'model': config.modelId,
          'prompt': prompt,
          'max_tokens': maxTokens,
          'temperature': temperature,
        },
      );
      final choices = res.data['choices'] as List;
      if (choices.isEmpty) throw const ApiException('Empty choices in response');
      return choices.first['text'] as String;
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _msg(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Is AIServer running?';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach server at ${config.baseUrl}. Is AIServer running?';
    }
    final status = e.response?.statusCode;
    final body = e.response?.data;
    if (status != null) {
      final errMsg = body is Map ? body['error'] ?? body.toString() : body;
      return 'Server error $status: $errMsg';
    }
    return e.message ?? 'Unknown error';
  }
}

// ── Value objects ─────────────────────────────────────────────────────────────

class HealthStatus {
  const HealthStatus({
    required this.ok,
    required this.modelLoaded,
    this.modelId,
    this.port,
    this.error,
  });

  final bool ok;
  final bool modelLoaded;
  final String? modelId;
  final int? port;
  final String? error;
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => 'ApiException: $message';
}
