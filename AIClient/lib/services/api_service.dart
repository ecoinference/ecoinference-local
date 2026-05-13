import 'dart:convert';

import 'package:dio/dio.dart';
import '../models/chat_message.dart';
import '../models/download_progress.dart';
import '../models/model_info.dart';
import '../models/server_config.dart';

/// REST client for the AIServer inference server.
///
/// Usage pattern (FlutterFlow-friendly singleton):
/// ```dart
/// ApiService.configure(config);          // once at connect time
/// final models = await ApiService.instance.getCatalog();
/// ```
///
/// All methods throw [ApiException] on failure.
class ApiService {
  ApiService._internal(this.config)
      : _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(minutes: 3),
          headers: {'Content-Type': 'application/json'},
        ));

  // ── Singleton ───────────────────────────────────────────────────────────────

  static ApiService? _instance;

  /// The configured singleton. Throws a [StateError] if [configure] has not
  /// been called. Works correctly in both debug and release builds.
  static ApiService get instance {
    if (_instance == null) {
      throw StateError(
        'ApiService is not configured. '
        'Call ApiService.configure(config) before accessing instance.',
      );
    }
    return _instance!;
  }

  /// True after [configure] has been called at least once.
  static bool get isConfigured => _instance != null;

  /// (Re-)configures the singleton. Safe to call multiple times — closes the
  /// previous Dio connection pool before replacing the instance.
  static void configure(ServerConfig config) {
    _instance?._dio.close(force: false); // drain in-flight requests gracefully
    _instance = ApiService._internal(config);
  }

  // ── Fields ──────────────────────────────────────────────────────────────────

  final ServerConfig config;
  final Dio _dio;

  // ── Health ──────────────────────────────────────────────────────────────────

  /// Returns the current server health snapshot.
  Future<HealthStatus> checkHealth() async {
    try {
      final res = await _dio.get('/health');
      return HealthStatus(
        ok: true,
        modelLoaded: res.data['model_loaded'] as bool? ?? false,
        modelId: res.data['model_id'] as String?,
        port: res.data['port'] as int? ?? config.port,
        downloadActive: res.data['download_active'] as bool? ?? false,
      );
    } on DioException catch (e) {
      return HealthStatus(ok: false, modelLoaded: false, error: _msg(e));
    }
  }

  // ── Catalog ─────────────────────────────────────────────────────────────────

  /// Returns the full model catalog with live downloaded / loaded state.
  Future<List<ModelInfo>> getCatalog() async {
    try {
      final res = await _dio.get('/v1/catalog');
      final models = res.data['models'] as List? ?? [];
      return models
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  // ── Download ─────────────────────────────────────────────────────────────────

  /// Triggers a download for [modelId]. Returns immediately (202 Accepted).
  /// Monitor progress with [watchDownloadProgress].
  ///
  /// Pass [hfToken] if the model is gated on HuggingFace — the token is
  /// forwarded to the server so it can authenticate the download request.
  /// Leave null on the first attempt; if the download progress stream emits
  /// a `license_required` error, prompt the user and retry with a token.
  Future<void> startDownload(String modelId, {String? hfToken}) async {
    try {
      final body = <String, dynamic>{'model_id': modelId};
      if (hfToken != null && hfToken.isNotEmpty) {
        body['hf_token'] = hfToken;
      }
      await _dio.post('/v1/models/download', data: body);
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  /// Streams [DownloadProgress] events via SSE until a terminal status arrives.
  ///
  /// Yields the current snapshot immediately, then streams updates. The stream
  /// closes after status becomes `complete`, `error`, or `cancelled`.
  Stream<DownloadProgress> watchDownloadProgress() async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        '/v1/models/download/progress',
        options: Options(
          responseType: ResponseType.stream,
          // Disable receive timeout for SSE: a large model (4 GB+) can take
          // 30+ minutes to download. The base 3-min timeout would cut the
          // stream long before the download finishes.
          receiveTimeout: Duration.zero,
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }

    var buffer = '';
    await for (final chunk in response.data!.stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') return;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final progress = DownloadProgress.fromJson(json);
          yield progress;
          if (progress.isTerminal) return;
        } catch (_) {
          // Skip malformed / partial JSON chunks.
        }
      }
    }
  }

  /// Cancels the active download. Throws [ApiException] if none is in progress.
  Future<void> cancelDownload() async {
    try {
      await _dio.delete('/v1/models/download');
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  /// Deletes the downloaded model file for [modelId] from the server device.
  Future<void> deleteModel(String modelId) async {
    try {
      await _dio.delete('/v1/models/$modelId');
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  // ── Load / unload ────────────────────────────────────────────────────────────

  /// Loads [modelId] into the inference engine. This call blocks until the
  /// model is fully loaded and ready (synchronous on the server side).
  Future<void> loadModel(
    String modelId, {
    bool useGpu = false,
    int maxNumTokens = 8192,
  }) async {
    try {
      final res = await _dio.post(
        '/v1/models/load',
        data: {
          'model_id': modelId,
          'use_gpu': useGpu,
          'max_num_tokens': maxNumTokens,
        },
        // Loading a large model can take 20–60 s — override default timeout.
        options: Options(receiveTimeout: const Duration(minutes: 2)),
      );
      final status = res.data['status'] as String?;
      if (status == 'error') {
        final err = res.data['error'] as String? ?? 'Unknown load error';
        throw ApiException('Load failed: $err');
      }
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  /// Unloads the currently loaded model and frees inference resources.
  Future<void> unloadModel() async {
    try {
      await _dio.post('/v1/models/unload');
    } on DioException catch (e) {
      throw ApiException(_msg(e));
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
      final choices = res.data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const ApiException('Empty choices in response');
      }
      final content =
          (choices.first as Map?)?['message']?['content'] as String?;
      if (content == null) {
        throw const ApiException('Missing content in response');
      }
      return content;
    } on DioException catch (e) {
      throw ApiException(_msg(e));
    }
  }

  /// Streams the assistant reply token-by-token via SSE (`stream: true`).
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
          final delta =
              choices.first['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } catch (_) {
          // Skip malformed / partial JSON chunks.
        }
      }
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
      final errMsg =
          body is Map ? body['error'] ?? body.toString() : body;
      return 'Server error $status: $errMsg';
    }
    // Verbose fallback — helps diagnose platform-specific network failures.
    final inner = e.error;
    return 'Error [${e.type.name}]: ${e.message ?? inner?.toString() ?? 'no details'}';
  }
}

// ── Value objects ─────────────────────────────────────────────────────────────

class HealthStatus {
  const HealthStatus({
    required this.ok,
    required this.modelLoaded,
    this.modelId,
    this.port,
    this.downloadActive = false,
    this.error,
  });

  final bool ok;
  final bool modelLoaded;
  final String? modelId;
  final int? port;
  final bool downloadActive;
  final String? error;
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => 'ApiException: $message';
}
