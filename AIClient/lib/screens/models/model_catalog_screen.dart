import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/download_progress.dart';
import '../../models/model_info.dart';
import '../../services/api_service.dart';

/// Displays the AIServer model catalog and lets the user download, load,
/// unload, and delete models.
///
/// Call with `await Navigator.push(...)` from ChatScreen or ConnectionScreen.
/// Returns the loaded model ID (String) when the user loads a model,
/// or null if they navigate back without loading one.
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

  // ── HF token ───────────────────────────────────────────────────────────────

  /// Persisted across screen re-entries via SharedPreferences.
  String? _hfToken;

  static const _kHfTokenKey = 'hf_token';

  @override
  void initState() {
    super.initState();
    _loadHfToken();
    _fetchCatalog();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadHfToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kHfTokenKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _hfToken = saved);
    }
  }

  Future<void> _saveHfToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token.isEmpty) {
      await prefs.remove(_kHfTokenKey);
    } else {
      await prefs.setString(_kHfTokenKey, token);
    }
  }

  // ── Catalog ────────────────────────────────────────────────────────────────

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
    // Prompt for an HF token the first time; reuse stored value on retries.
    if (_hfToken == null || _hfToken!.isEmpty) {
      final token = await _promptHfToken();
      if (token == null) return; // user cancelled
      setState(() => _hfToken = token.isEmpty ? null : token);
      await _saveHfToken(token);
    }

    try {
      await ApiService.instance.startDownload(model.id, hfToken: _hfToken);
    } on ApiException catch (e) {
      if (mounted) _showSnack('Download failed: ${e.message}');
      return;
    }

    if (!mounted) return;
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
          // FIX: handle stream closing without a terminal event (network
          // drop, server restart) — clear downloading state so the UI
          // doesn't stay stuck.
          onDone: () {
            if (!mounted) return;
            if (_downloadingId != null) {
              setState(() {
                _downloadingId = null;
                _downloadProgress = null;
              });
              _fetchCatalog();
            }
          },
          cancelOnError: true,
        );
  }

  void _onDownloadTerminal(DownloadProgress progress) {
    // Guard against use-after-dispose: callbacks can fire just after dispose
    // cancels the subscription due to microtask scheduling.
    if (!mounted) return;

    _progressSub?.cancel();
    _progressSub = null;

    if (progress.status == 'complete') {
      _fetchCatalog();
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
      if (mounted) _showSnack('Cancel failed: ${e.message}');
    }
    // Terminal event from the SSE stream will clean up _downloadingId state.
  }

  // ── Load / Unload ──────────────────────────────────────────────────────────

  Future<void> _loadModel(ModelInfo model) async {
    setState(() => _loadingId = model.id);
    try {
      await ApiService.instance.loadModel(model.id);
      if (!mounted) return;
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
      if (!mounted) return; // FIX: guard before async _fetchCatalog
      await _fetchCatalog();
    } on ApiException catch (e) {
      if (mounted) _showSnack('Unload failed: ${e.message}');
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
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.instance.deleteModel(model.id);
      if (!mounted) return;
      await _fetchCatalog();
    } on ApiException catch (e) {
      if (mounted) _showSnack('Delete failed: ${e.message}');
    }
  }

  // ── HF token dialog ────────────────────────────────────────────────────────

  /// Shows the HF token dialog. The [TextEditingController] is created and
  /// disposed inside a [StatefulBuilder] so it has a proper lifecycle.
  Future<String?> _promptHfToken() {
    return showDialog<String>(
      context: context,
      builder: (_) => _HfTokenDialog(initialToken: _hfToken ?? ''),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String message) {
    if (!mounted) return;
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
          // Disable all destructive actions while any download is active.
          actionsEnabled: _downloadingId == null && _loadingId == null,
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

// ── HF token dialog (own StatefulWidget so controller is properly disposed) ────

class _HfTokenDialog extends StatefulWidget {
  const _HfTokenDialog({required this.initialToken});
  final String initialToken;

  @override
  State<_HfTokenDialog> createState() => _HfTokenDialogState();
}

class _HfTokenDialogState extends State<_HfTokenDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _ctrl.dispose(); // FIX: controller always disposed with the widget
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
            controller: _ctrl,
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
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Continue'),
        ),
      ],
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
    required this.actionsEnabled,
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
  final bool actionsEnabled;
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
            // ── Header row ────────────────────────────────────────────────────
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

            // ── Status chips ──────────────────────────────────────────────────
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
              actionsEnabled: actionsEnabled,
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
    final received = progress?.bytesReceived ?? 0;
    final total = progress?.totalBytes ?? 0;

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
              : '$pct% — ${_formatBytes(received)} / ${_formatBytes(total)}',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// FIX: shows GB for large models instead of a 4-digit MB number.
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final gb = bytes / 1024 / 1024 / 1024;
    if (gb >= 1.0) return '${gb.toStringAsFixed(1)} GB';
    final mb = bytes / 1024 / 1024;
    return '${mb.toStringAsFixed(0)} MB';
  }
}

// ── Action row ────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.model,
    required this.isDownloading,
    required this.isLoadingModel,
    required this.actionsEnabled,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  final ModelInfo model;
  final bool isDownloading;
  final bool isLoadingModel;

  /// When false (another model is loading/downloading), buttons are disabled
  /// to prevent concurrent operations.
  final bool actionsEnabled;

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
            // Disable if another operation is in progress.
            onPressed: actionsEnabled ? onDownload : null,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Download'),
          ),
        if (model.downloaded && !model.loaded)
          FilledButton.icon(
            onPressed: actionsEnabled ? onLoad : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Load'),
          ),
        if (model.loaded)
          OutlinedButton.icon(
            onPressed: actionsEnabled ? onUnload : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Unload'),
          ),
        if (model.downloaded)
          OutlinedButton.icon(
            onPressed: actionsEnabled ? onDelete : null,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: actionsEnabled
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.outline,
            ),
            label: Text(
              'Delete',
              style: TextStyle(
                color: actionsEnabled
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Reusable chip ─────────────────────────────────────────────────────────────

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

// ── Error state ───────────────────────────────────────────────────────────────

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
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
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
