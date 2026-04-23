import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/model_info.dart';
import '../services/settings_service.dart';

typedef ProgressCallback = void Function(double progress, int receivedBytes, int totalBytes);

/// Handles downloading Gemma model files from Kaggle.
///
/// Kaggle requires HTTP Basic auth: username:apiKey (base64-encoded).
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
    followRedirects: true,
    maxRedirects: 5,
  ));

  CancelToken? _cancelToken;

  /// Returns the directory where model files are stored.
  Future<Directory> get modelsDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Full path of a downloaded model file.
  Future<String> modelFilePath(ModelInfo model) async {
    final dir = await modelsDir;
    return '${dir.path}/${model.fileName}';
  }

  /// True if the model file already exists on disk.
  Future<bool> isDownloaded(ModelInfo model) async {
    final path = await modelFilePath(model);
    return File(path).existsSync();
  }

  /// Downloads [model] from Kaggle, reporting progress via [onProgress].
  /// Throws [DownloadException] on any error.
  Future<String> download(
    ModelInfo model, {
    ProgressCallback? onProgress,
  }) async {
    final settings = SettingsService.instance;
    if (!settings.hasKaggleCredentials) {
      throw DownloadException('Kaggle credentials not set.');
    }

    final credentials = base64Encode(
      utf8.encode('${settings.kaggleUsername}:${settings.kaggleKey}'),
    );

    final savePath = await modelFilePath(model);
    _cancelToken = CancelToken();

    try {
      await _dio.download(
        model.downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        options: Options(
          headers: {'Authorization': 'Basic $credentials'},
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress?.call(received / total, received, total);
        },
        deleteOnError: true,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw DownloadException('Download cancelled.');
      }
      throw DownloadException('Download error: ${e.message}');
    }

    // Optional SHA-256 verification.
    if (model.sha256 != null) {
      await _verifySha256(savePath, model.sha256!);
    }

    return savePath;
  }

  /// Cancels an in-progress download.
  void cancel() => _cancelToken?.cancel('User cancelled');

  /// Deletes a downloaded model file.
  Future<void> deleteModel(ModelInfo model) async {
    final path = await modelFilePath(model);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  Future<void> _verifySha256(String filePath, String expected) async {
    final bytes = await File(filePath).readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      File(filePath).deleteSync();
      throw DownloadException(
          'SHA-256 mismatch. Expected $expected, got $actual');
    }
  }
}

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => 'DownloadException: $message';
}
