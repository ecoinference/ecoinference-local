/// Describes one entry in the model catalogue.
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.parameterCount,
    required this.fileSizeMb,
    required this.downloadUrl,
    required this.fileName,
    this.sha256,
  });

  final String id;
  final String displayName;
  final String description;
  final String parameterCount;
  final int fileSizeMb;
  final String downloadUrl;
  final String fileName;
  final String? sha256; // hex-encoded, optional verification

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'parameterCount': parameterCount,
        'fileSizeMb': fileSizeMb,
      };
}
