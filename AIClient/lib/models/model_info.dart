/// A single entry from the AIServer model catalog (`GET /v1/catalog`).
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sizeGb,
    required this.platform,
    this.requiresHfToken = false,
    this.licenseUrl,
    this.downloaded = false,
    this.loaded = false,
  });

  /// Catalog identifier, e.g. `gemma4-e2b-it`.
  final String id;

  /// Human-readable name, e.g. `Gemma 4 E2B`.
  final String name;

  /// File name on disk, e.g. `gemma-4-E2B-it.litertlm`.
  final String fileName;

  /// Approximate model size in GB (for display only).
  final double sizeGb;

  /// `"android"` | `"ios"` | `"all"`.
  final String platform;

  /// True when the model requires a HuggingFace access token.
  /// The token is only needed after accepting the licence once in a browser.
  final bool requiresHfToken;

  /// HuggingFace model page URL — opened so the user can accept the licence.
  /// Null for models that never require auth.
  final String? licenseUrl;

  /// True when the model file is present on the server device.
  final bool downloaded;

  /// True when this model is currently loaded in the inference engine.
  final bool loaded;

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
        id: json['id'] as String,
        // Server sends 'display_name'; accept legacy 'name' for test fixtures.
        name: (json['display_name'] ?? json['name']) as String,
        fileName: json['file_name'] as String,
        // Server sends size as integer MB ('file_size_mb'); convert to GB.
        // Accept 'size_gb' for test fixtures that already use that key.
        sizeGb: json['size_gb'] != null
            ? (json['size_gb'] as num).toDouble()
            : (json['file_size_mb'] as num).toDouble() / 1024,
        platform: json['platform'] as String,
        requiresHfToken: json['requires_hf_token'] as bool? ?? false,
        licenseUrl: json['license_url'] as String?,
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
        requiresHfToken: requiresHfToken,
        licenseUrl: licenseUrl,
        downloaded: downloaded ?? this.downloaded,
        loaded: loaded ?? this.loaded,
      );
}
