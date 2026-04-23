import '../models/model_info.dart';

/// iOS-compatible Gemma models in MediaPipe .task format.
///
/// ⚠️  Gemma 4 (.litertlm) is NOT yet supported on iOS — the MediaPipe
///     LlmInference backend crashes at inference time with Gemma 4 models.
///     Gemma 4 works on Android only; iOS requires .task format models.
///
/// Confirmed working on iOS with flutter_gemma 0.13.6 / MediaPipe 0.10.33:
///   • Gemma 3n E2B  — 3.1 GB, instruction-tuned, gated (HF token required)
///   • Gemma 3 1B    — 0.5 GB, instruction-tuned, public (no token needed)
///
/// HuggingFace licence acceptance required once in browser for gated models:
///   https://huggingface.co/google/gemma-3n-E2B-it-litert-preview

class ModelCatalog {
  ModelCatalog._();

  static const String _hfBase = 'https://huggingface.co';

  static final List<ModelInfo> models = [
    ModelInfo(
      id: 'gemma3n-e2b-it',
      displayName: 'Gemma 3n E2B',
      description:
          'Gemma 3 Nano effective-2B, instruction-tuned. '
          'Best quality for on-device inference; requires HuggingFace token '
          'and ~3.1 GB storage.',
      parameterCount: 'E2B',
      fileSizeMb: 3100,
      downloadUrl:
          '$_hfBase/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
      fileName: 'gemma-3n-E2B-it-int4.task',
      sha256: null,
    ),
    ModelInfo(
      id: 'gemma3-1b-it',
      displayName: 'Gemma 3 1B',
      description:
          'Gemma 3 1B, instruction-tuned. '
          'Fastest and smallest option (~0.5 GB). '
          'No HuggingFace token required.',
      parameterCount: '1B',
      fileSizeMb: 500,
      downloadUrl:
          '$_hfBase/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
      fileName: 'gemma3-1b-it-int4.task',
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
