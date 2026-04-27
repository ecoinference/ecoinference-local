/// SSE event from `GET /v1/models/download/progress`.
class DownloadProgress {
  const DownloadProgress({
    required this.modelId,
    required this.status,
    this.percent = 0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.error,
  });

  final String modelId;

  /// `"downloading"` | `"complete"` | `"error"` | `"cancelled"`.
  final String status;

  final int percent;
  final int bytesReceived;
  final int totalBytes;
  final String? error;

  /// True once the download has left the `"downloading"` state.
  bool get isTerminal => status != 'downloading';

  factory DownloadProgress.fromJson(Map<String, dynamic> json) =>
      DownloadProgress(
        modelId: json['model_id'] as String,
        status: json['status'] as String,
        percent: json['percent'] as int? ?? 0,
        bytesReceived: (json['bytes_received'] as num?)?.toInt() ?? 0,
        totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
      );
}
