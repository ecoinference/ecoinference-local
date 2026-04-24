import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/model_info.dart';

/// Resolves model file paths and checks on-disk existence.
///
/// Downloads are now handled by flutter_gemma's [FlutterGemma.installModel]
/// builder with [fromNetwork], which manages the foreground service,
/// retry logic, and progress reporting internally.
///
/// This service is kept as a thin utility so the rest of the app has a
/// single place to compute the canonical model file path.
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  /// Full path of a model file on disk.
  ///
  /// flutter_gemma's [fromNetwork] handler stores files directly in
  /// [getApplicationDocumentsDirectory], so this path matches what
  /// [FlutterGemma.isModelInstalled] and [InferenceService.loadModel] expect.
  Future<String> modelFilePath(ModelInfo model) async {
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/${model.fileName}';
  }

  /// Returns true if the model file is present on disk.
  Future<bool> isDownloaded(ModelInfo model) async {
    final path = await modelFilePath(model);
    return File(path).existsSync();
  }

  /// Deletes a downloaded model file from disk.
  ///
  /// Call [FlutterGemma.uninstallModel] first to remove the flutter_gemma
  /// metadata entry before deleting the file.
  Future<void> deleteModel(ModelInfo model) async {
    final path = await modelFilePath(model);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
