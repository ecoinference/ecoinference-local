import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/model_catalog.dart';
import '../../services/inference_service.dart';
import '../../services/server_service.dart';
import '../../services/settings_service.dart';
import '../../services/download_service.dart';
import '../settings/settings_screen.dart';

/// Main screen shown once setup is complete.
/// Loads the model, starts the server, and displays connection info.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _serverRunning = false;
  String? _error;
  String? _modelId;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final settings = SettingsService.instance;
    _modelId = settings.selectedModelId;

    if (_modelId == null) {
      setState(() {
        _error = 'No model selected. Please run setup again.';
        _loading = false;
      });
      return;
    }

    try {
      // Load model into the native inference engine.
      final model = ModelCatalog.findById(_modelId!);
      if (model == null) throw Exception('Unknown model: $_modelId');

      final modelPath =
          await DownloadService.instance.modelFilePath(model);
      await InferenceService.instance.loadModel(modelPath, _modelId!);

      // Start the REST server.
      await ServerService.instance.start();

      setState(() {
        _serverRunning = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleServer() async {
    if (_serverRunning) {
      await ServerService.instance.stop();
      setState(() => _serverRunning = false);
    } else {
      try {
        await ServerService.instance.start();
        setState(() => _serverRunning = true);
      } catch (e) {
        _showError(e.toString());
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final port = SettingsService.instance.port;
    final endpoint = 'http://127.0.0.1:$port';
    final modelInfo = _modelId != null ? ModelCatalog.findById(_modelId!) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma 4 Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              // Restart if port changed.
              if (ServerService.instance.isRunning) {
                await ServerService.instance.stop();
                await ServerService.instance.start();
                setState(() => _serverRunning = true);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildStatus(theme, endpoint, port, modelInfo),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Loading model…',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few seconds on first run.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Error', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _boot,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme, String endpoint, int port, modelInfo) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status card
          _StatusCard(isRunning: _serverRunning, onToggle: _toggleServer),
          const SizedBox(height: 20),

          // Endpoint info
          if (_serverRunning) ...[
            _InfoCard(
              icon: Icons.link,
              title: 'Base URL',
              value: endpoint,
              copyable: true,
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.hub_outlined,
              title: 'Model',
              value: modelInfo?.displayName ?? _modelId ?? '—',
            ),
            const SizedBox(height: 20),

            // Endpoint reference
            Text('Available Endpoints',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _EndpointList(baseUrl: endpoint),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isRunning, required this.onToggle});
  final bool isRunning;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        isRunning ? Colors.green.shade600 : theme.colorScheme.outline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isRunning ? 'Server running' : 'Server stopped',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(value: isRunning, onChanged: (_) => onToggle()),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.labelMedium),
        subtitle: Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        trailing: copyable
            ? IconButton(
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1)),
                  );
                },
              )
            : null,
      ),
    );
  }
}

class _EndpointList extends StatelessWidget {
  const _EndpointList({required this.baseUrl});
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('GET', '$baseUrl/health'),
      ('GET', '$baseUrl/v1/models'),
      ('POST', '$baseUrl/v1/models/load'),
      ('POST', '$baseUrl/v1/chat/completions'),
      ('POST', '$baseUrl/v1/completions'),
    ];
    final theme = Theme.of(context);
    return Column(
      children: entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: e.$1 == 'GET'
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(e.$1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: e.$1 == 'GET'
                              ? Colors.blue.shade700
                              : Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(e.$2,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
