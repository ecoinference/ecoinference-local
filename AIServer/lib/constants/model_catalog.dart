import '../models/model_info.dart';

/// Models are hosted on HuggingFace as LiteRT .task files.
/// These are the formats required by flutter_gemma / Google AI Edge
/// LLM Inference API.
///
/// License acceptance required at:
///   https://huggingface.co/litert-community/Gemma3-1B-IT
///   https://huggingface.co/litert-community/Gemma3-4B-IT
///
/// Note: Gemma 4 LiteRT files are not yet published. Gemma 3 is the
/// latest generation available in .task format. This catalog will be
/// updated when Gemma 4 LiteRT artefacts are released.

class ModelCatalog {
  ModelCatalog._();

  static const String _hfBase = 'https://huggingface.co';

  static final List<ModelInfo> models = [
    ModelInfo(
      id: 'gemma3-1b-it-int4',
      displayName: 'Gemma 3 1B (INT4)',
      description:
          'Instruction-tuned, 4-bit quantised. Runs on all devices, '
          'fast inference.',
      parameterCount: '1B',
      fileSizeMb: 700,
      downloadUrl:
          '$_hfBase/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
      fileName: 'gemma3-1b-it-int4.task',
      sha256: null,
    ),
    ModelInfo(
      id: 'gemma3-4b-it-int4',
      displayName: 'Gemma 3 4B (INT4)',
      description:
          'Instruction-tuned, 4-bit quantised. Better quality; '
          'needs ≥6 GB RAM.',
      parameterCount: '4B',
      fileSizeMb: 2600,
      downloadUrl:
          '$_hfBase/litert-community/Gemma3-4B-IT/resolve/main/gemma3-4b-it-int4.task',
      fileName: 'gemma3-4b-it-int4.task',
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
