import 'package:flutter/material.dart';
import '../../models/model_info.dart';
import '../../services/download_service.dart';

/// Shows download progress for a model file.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({
    super.key,
    required this.model,
    required this.onComplete,
  });

  final ModelInfo model;
  final VoidCallback onComplete;

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  double _progress = 0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  bool _downloading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    try {
      await DownloadService.instance.download(
        widget.model,
        onProgress: (progress, received, total) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _receivedBytes = received;
            _totalBytes = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _done = true;
        _downloading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _downloading = false;
      });
    }
  }

  void _cancel() {
    DownloadService.instance.cancel();
    Navigator.of(context).pop();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloading'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _done
                    ? Icons.check_circle_rounded
                    : _error != null
                        ? Icons.error_rounded
                        : Icons.downloading_rounded,
                size: 72,
                color: _done
                    ? theme.colorScheme.primary
                    : _error != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.secondary,
              ),
              const SizedBox(height: 24),
              Text(
                widget.model.displayName,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_downloading) ...[
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  _totalBytes > 0
                      ? '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}'
                      : 'Connecting…',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              ] else if (_done) ...[
                Text('Download complete!',
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: widget.onComplete,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Server'),
                  ),
                ),
              ] else if (_error != null) ...[
                Text(
                  'Download failed',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
