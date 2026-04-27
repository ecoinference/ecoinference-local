/// A single entry from the AIServer model catalog (`GET /v1/catalog`).
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sizeGb,
    required this.platform,
    this.downloaded = false,
    this.loaded = false,
  });

  /// Catalog identifier, e.g. `gemma4-e2b-it-litert-preview`.
  final String id;

  /// Human-readable name, e.g. `Gemma 4 E2B`.
  final String name;

  /// File name on disk, e.g. `gemma4-e2b-it-lm-v1.litertlm`.
  final String fileName;

  /// Approximate model size in GB (for display only).
  final double sizeGb;

  /// `"android"` | `"ios"` | `"all"`.
  final String platform;

  /// True when the model file is present on the server device.
  final bool downloaded;

  /// True when this model is currently loaded in the inference engine.
  final bool loaded;

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        fileName: json['file_name'] as String,
        sizeGb: (json['size_gb'] as num).toDouble(),
        platform: json['platform'] as String,
        downloaded: json['downloaded'] as bool? ?? false,
        loaded: json['loaded'] as bool? ?? false,
      );

  /// Returns a copy with updated live-state fields.
  ModelInfo copyWith({bool? downloaded, bool? loaded}) => ModelInfo(
        id: id,
        name: name,
        fileName: fileName,
        sizeGb: sizeGb,
        platform: platform,
        downloaded: downloaded ?? this.downloaded,
        loaded: loaded ?? this.loaded,
      );
}
