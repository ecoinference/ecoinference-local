import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/download_progress.dart';
import '../../models/model_info.dart';
import '../../services/api_service.dart';

/// Displays the AIServer model catalog and lets the user download, load,
/// unload, and delete models.
///
/// Call with `await Navigator.push(...)` from ChatScreen or ConnectionScreen.
/// Returns the loaded model ID (String) when the user confirms a model is
/// ready, or null if they navigate back without loading one.
class ModelCatalogScreen extends StatefulWidget {
  const ModelCatalogScreen({super.key});

  @override
  State<ModelCatalogScreen> createState() => _ModelCatalogScreenState();
}

class _ModelCatalogScreenState extends State<ModelCatalogScreen> {
  List<ModelInfo> _models = [];
  bool _loading = true;
  String? _error;

  // ── Download state ─────────────────────────────────────────────────────────

  /// Model ID currently being downloaded, or null.
  String? _downloadingId;

  /// Latest progress event for the active download.
  DownloadProgress? _downloadProgress;

  StreamSubscription<DownloadProgress>? _progressSub;

  // ── Load state ─────────────────────────────────────────────────────────────

  /// Model ID currently being loaded into the inference engine, or null.
  String? _loadingId;

  // ── HF token (optional) ───────────────────────────────────────────────────

  String? _hfToken;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _fetchCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await ApiService.instance.getCatalog();
      if (mounted) setState(() => _models = models);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Download ───────────────────────────────────────────────────────────────

  Future<void> _startDownload(ModelInfo model) async {
    // If no token stored yet, prompt first.
    if (_hfToken == null || _hfToken!.isEmpty) {
      final token = await _promptHfToken();
      if (token == null) return;
      _hfToken = token;
    }

    try {
      await ApiService.instance.startDownload(model.id, hfToken: _hfToken);
    } on ApiException catch (e) {
      if (mounted) _showSnack('Download failed: ${e.message}');
      return;
    }

    setState(() {
      _downloadingId = model.id;
      _downloadProgress = null;
    });

    _progressSub?.cancel();
    _progressSub = ApiService.instance
        .watchDownloadProgress()
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() => _downloadProgress = progress);
            if (progress.isTerminal) {
              _onDownloadTerminal(progress);
            }
          },
          onError: (Object e) {
            if (!mounted) return;
            final msg = e is ApiException ? e.message : e.toString();
            _showSnack('Progress stream error: $msg');
            setState(() {
              _downloadingId = null;
              _downloadProgress = null;
            });
          },
        );
  }

  void _onDownloadTerminal(DownloadProgress progress) {
    _progressSub?.cancel();
    _progressSub = null;

    if (progress.status == 'complete') {
      _fetchCatalog(); // refresh downloaded state
      _showSnack('Download complete');
    } else if (progress.status == 'error') {
      _showSnack('Download error: ${progress.error ?? 'Unknown'}');
    } else if (progress.status == 'cancelled') {
      _showSnack('Download cancelled');
    }

    setState(() {
      _downloadingId = null;
      _downloadProgress = null;
    });
  }

  Future<void> _cancelDownload() async {
    try {
      await ApiService.instance.cancelDownload();
    } on ApiException catch (e) {
      _showSnack('Cancel failed: ${e.message}');
    }
    // Terminal event from the SSE stream will clean up state.
  }

  // ── Load / Unload ──────────────────────────────────────────────────────────

  Future<void> _loadModel(ModelInfo model) async {
    setState(() => _loadingId = model.id);
    try {
      await ApiService.instance.loadModel(model.id);
      if (!mounted) return;
      // Refresh catalog so loaded badge updates, then pop with the model id.
      await _fetchCatalog();
      if (!mounted) return;
      Navigator.of(context).pop(model.id);
    } on ApiException catch (e) {
      if (mounted) _showSnack('Load failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _loadingId = null);
    }
  }

  Future<void> _unloadModel(ModelInfo model) async {
    try {
      await ApiService.instance.unloadModel();
      await _fetchCatalog();
    } on ApiException catch (e) {
      _showSnack('Unload failed: ${e.message}');
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _deleteModel(ModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text(
          'This will remove "${model.name}" from the device. '
          'You will need to download it again to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.instance.deleteModel(model.id);
      await _fetchCatalog();
    } on ApiException catch (e) {
      if (mounted) _showSnack('Delete failed: ${e.message}');
    }
  }

  // ── HF token dialog ────────────────────────────────────────────────────────

  Future<String?> _promptHfToken() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hugging Face Token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gemma 4 models require a Hugging Face token with model access. '
              'Leave blank to attempt an unauthenticated download.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'hf_...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetchCatalog,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _models.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _models.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _fetchCatalog);
    }
    return RefreshIndicator(
      onRefresh: _fetchCatalog,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _models.length,
        itemBuilder: (context, i) => _ModelCard(
          model: _models[i],
          isDownloading: _models[i].id == _downloadingId,
          downloadProgress: _models[i].id == _downloadingId
              ? _downloadProgress
              : null,
          isLoadingModel: _models[i].id == _loadingId,
          onDownload: () => _startDownload(_models[i]),
          onCancelDownload: _cancelDownload,
          onLoad: () => _loadModel(_models[i]),
          onUnload: () => _unloadModel(_models[i]),
          onDelete: () => _deleteModel(_models[i]),
        ),
      ),
    );
  }
}

// ── Model card ────────────────────────────────────────────────────────────────

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.isDownloading,
    required this.downloadProgress,
    required this.isLoadingModel,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  final ModelInfo model;
  final bool isDownloading;
  final DownloadProgress? downloadProgress;
  final bool isLoadingModel;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '${model.sizeGb.toStringAsFixed(1)} GB',
                  color: theme.colorScheme.surfaceContainerHighest,
                  textColor: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Status chips ─────────────────────────────────────────────────
            Wrap(
              spacing: 6,
              children: [
                if (model.loaded)
                  _Chip(
                    label: 'Loaded',
                    color: theme.colorScheme.primaryContainer,
                    textColor: theme.colorScheme.onPrimaryContainer,
                  )
                else if (model.downloaded)
                  _Chip(
                    label: 'Downloaded',
                    color: theme.colorScheme.secondaryContainer,
                    textColor: theme.colorScheme.onSecondaryContainer,
                  )
                else
                  _Chip(
                    label: 'Not downloaded',
                    color: theme.colorScheme.surfaceContainerHighest,
                    textColor: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),

            // ── Download progress bar ─────────────────────────────────────────
            if (isDownloading) ...[
              const SizedBox(height: 12),
              _DownloadProgressBar(progress: downloadProgress),
            ],

            const SizedBox(height: 12),

            // ── Action buttons ────────────────────────────────────────────────
            _ActionRow(
              model: model,
              isDownloading: isDownloading,
              isLoadingModel: isLoadingModel,
              onDownload: onDownload,
              onCancelDownload: onCancelDownload,
              onLoad: onLoad,
              onUnload: onUnload,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Download progress bar ─────────────────────────────────────────────────────

class _DownloadProgressBar extends StatelessWidget {
  const _DownloadProgressBar({this.progress});

  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = progress?.percent ?? 0;
    final isIndeterminate = pct == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: isIndeterminate ? null : pct / 100,
        ),
        const SizedBox(height: 4),
        Text(
          isIndeterminate
              ? 'Starting…'
              : '$pct% — ${_mb(progress?.bytesReceived ?? 0)} / '
                  '${_mb(progress?.totalBytes ?? 0)} MB',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(0);
}

// ── Action row ────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.model,
    required this.isDownloading,
    required this.isLoadingModel,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  final ModelInfo model;
  final bool isDownloading;
  final bool isLoadingModel;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (isDownloading) {
      return OutlinedButton.icon(
        onPressed: onCancelDownload,
        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: const Text('Cancel Download'),
      );
    }

    if (isLoadingModel) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Loading model…'),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!model.downloaded)
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Download'),
          ),
        if (model.downloaded && !model.loaded)
          FilledButton.icon(
            onPressed: onLoad,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Load'),
          ),
        if (model.loaded)
          OutlinedButton.icon(
            onPressed: onUnload,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Unload'),
          ),
        if (model.downloaded)
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              'Delete',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

// ── Reusable chip ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: textColor, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
