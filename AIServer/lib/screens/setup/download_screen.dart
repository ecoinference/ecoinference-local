import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../../models/model_info.dart';
import '../../services/settings_service.dart';

/// Shows download progress for a model file.
///
/// Uses flutter_gemma's [FlutterGemma.installModel] with [fromNetwork] so that
/// on Android the download runs inside a foreground service (with a persistent
/// notification), keeping it alive even when the user backgrounds the app.
/// The foreground: null default in fromNetwork() auto-enables the foreground
/// service for files >500 MB — all catalog models qualify.
///
/// After [install] returns the model is registered AND set as the active
/// inference model, so [InferenceService.loadModel] will skip re-downloading
/// on the first boot.
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
  bool _downloading = false;
  bool _done = false;
  String? _error;

  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    // Cancel any in-flight download when the widget is torn down.
    _cancelToken?.cancel('Screen disposed');
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_downloading) return; // guard against concurrent calls (e.g. double-tap Retry)
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    _cancelToken = CancelToken();

    // Detect .litertlm vs .task from the filename so the correct engine is used.
    final fileType = widget.model.fileName.endsWith('.litertlm')
        ? ModelFileType.litertlm
        : ModelFileType.task;

    final hfToken = SettingsService.instance.hfToken;

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: fileType,
      )
          .fromNetwork(
            widget.model.downloadUrl,
            // Pass the token only when one is configured; flutter_gemma will
            // automatically use the global HF token for huggingface.co URLs.
            token: hfToken.isNotEmpty ? hfToken : null,
            // null = auto: uses foreground service on Android when file >500 MB.
          )
          .withProgress((int percent) {
            if (!mounted) return;
            setState(() => _progress = percent / 100.0);
          })
          .withCancelToken(_cancelToken!)
          .install();

      if (!mounted) return;
      setState(() {
        _done = true;
        _downloading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Distinguish user-initiated cancellation from real errors.
      if (e is DownloadCancelledException) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = e.toString();
        _downloading = false;
      });
    }
  }

  void _cancel() {
    _cancelToken?.cancel('User cancelled');
    // Navigation happens in the catch block after cancellation propagates.
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
                  _progress > 0
                      ? '${(_progress * 100).toStringAsFixed(0)}%'
                      : 'Connecting…',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '~${widget.model.fileSizeMb >= 1024 ? '${(widget.model.fileSizeMb / 1024).toStringAsFixed(1)} GB' : '${widget.model.fileSizeMb} MB'} total',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
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
