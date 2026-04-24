import '../models/model_info.dart';

/// Platform-aware model catalogue.
///
/// Android  → Gemma 4 .litertlm  (LiteRT-LM runtime, full Gemma 4 support)
/// iOS      → Gemma 3n / Gemma 3 .task  (MediaPipe runtime; Gemma 4 crashes on iOS)
///
/// HuggingFace licence acceptance required (one-time in browser) for gated models:
///   Gemma 4  E2B: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
///   Gemma 4  E4B: https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
///   Gemma 3n E2B: https://huggingface.co/google/gemma-3n-E2B-it-litert-preview

class ModelCatalog {
  ModelCatalog._();

  static const String _hfBase = 'https://huggingface.co';

  // ── Android models (Gemma 4, .litertlm) ──────────────────────────────────
  // Intentionally kept; switch `models` getter to this once the
  // litert_compiled_model.cc:353 regression is fixed in litertlm-android.
  // Tracked: https://github.com/google-ai-edge/gallery/issues/557
  // ignore: unused_field
  static final List<ModelInfo> _androidModels = [
    ModelInfo(
      id: 'gemma4-e2b-it',
      displayName: 'Gemma 4 E2B',
      description:
          'Gemma 4 effective-2B, instruction-tuned. '
          'Good balance of speed and quality on most devices (~2.6 GB).',
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

  // ── iOS models (Gemma 3n / Gemma 3, .task) ───────────────────────────────

  static final List<ModelInfo> _iosModels = [
    ModelInfo(
      id: 'gemma3n-e2b-it',
      displayName: 'Gemma 3n E2B',
      description:
          'Gemma 3 Nano effective-2B, instruction-tuned. '
          'Best quality for iOS; requires HuggingFace token and ~3.1 GB storage.',
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

  // ── Public API ────────────────────────────────────────────────────────────

  static List<ModelInfo> get models => _iosModels;

  static ModelInfo? findById(String id) {
    try {
      return models.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
