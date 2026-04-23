import '../models/model_info.dart';

/// Gemma 4 LiteRT models from the litert-community org on HuggingFace.
///
/// File format: .litertlm  (LiteRT LM runtime — iOS + Android text inference)
/// Note: the -web.task files in the same repos are web-only; do not use them.
///
/// "E2B" / "E4B" = Effective 2B / 4B parameters (Gemma 4 architecture).
///
/// License acceptance required (one-time, in browser) at:
///   https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
///   https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm

class ModelCatalog {
  ModelCatalog._();

  static const String _hfBase = 'https://huggingface.co';

  static final List<ModelInfo> models = [
    ModelInfo(
      id: 'gemma4-e2b-it',
      displayName: 'Gemma 4 E2B',
      description:
          'Gemma 4 effective-2B, instruction-tuned. '
          'Good balance of speed and quality on most devices.',
      parameterCount: 'E2B',
      fileSizeMb: 2580,
      downloadUrl:
          '$_hfBase/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      fileName: 'gemma-4-E2B-it.litertlm',
      sha256: null,
    ),
    ModelInfo(
      id: 'gemma4-e4b-it',
      displayName: 'Gemma 4 E4B',
      description:
          'Gemma 4 effective-4B, instruction-tuned. '
          'Best quality; needs ≥6 GB RAM and ~3.7 GB storage.',
      parameterCount: 'E4B',
      fileSizeMb: 3650,
      downloadUrl:
          '$_hfBase/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      fileName: 'gemma-4-E4B-it.litertlm',
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
