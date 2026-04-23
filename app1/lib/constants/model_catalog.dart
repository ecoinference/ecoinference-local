import '../models/model_info.dart';

/// Kaggle model download URLs follow the pattern:
///   https://www.kaggle.com/api/v1/models/{owner}/{model}/{framework}/{variation}/{version}/download
///
/// flutter_gemma uses .bin files (MediaPipe CPU/GPU int4 format).
/// Models are hosted under the 'tfLite' framework on Kaggle Models.

class ModelCatalog {
  ModelCatalog._();

  static const String _kaggleBase =
      'https://www.kaggle.com/api/v1/models/google';

  static final List<ModelInfo> models = [
    ModelInfo(
      id: 'gemma4-1b-it-int4',
      displayName: 'Gemma 4 1B (INT4)',
      description:
          'Instruction-tuned, 4-bit quantised. Best for older/low-RAM devices.',
      parameterCount: '1B',
      fileSizeMb: 650,
      downloadUrl:
          '$_kaggleBase/gemma-4/tfLite/gemma4-1b-it-gpu-int4/1/download',
      fileName: 'gemma4-1b-it-gpu-int4.bin',
      // SHA-256 to be updated once Google publishes the Gemma 4 artefacts.
      sha256: null,
    ),
    ModelInfo(
      id: 'gemma4-4b-it-int4',
      displayName: 'Gemma 4 4B (INT4)',
      description:
          'Instruction-tuned, 4-bit quantised. Better quality; needs ≥6 GB RAM.',
      parameterCount: '4B',
      fileSizeMb: 2500,
      downloadUrl:
          '$_kaggleBase/gemma-4/tfLite/gemma4-4b-it-gpu-int4/1/download',
      fileName: 'gemma4-4b-it-gpu-int4.bin',
      sha256: null,
    ),
  ];

  static ModelInfo? findById(String id) {
    try {
      return models.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
