import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/server_config.dart';
import '../../services/api_service.dart';
import '../../services/server_launcher.dart';
import '../chat/chat_screen.dart';
import '../models/model_catalog_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _hostCtrl = TextEditingController(text: '127.0.0.1');
  final _portCtrl = TextEditingController(text: '8080');
  bool _checking = false;
  bool _launching = false;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostCtrl.text = prefs.getString('server_host') ?? '127.0.0.1';
      _portCtrl.text = (prefs.getInt('server_port') ?? 8080).toString();
    });
  }

  // ── Launch server ──────────────────────────────────────────────────────────

  Future<void> _launchServer() async {
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      await ServerLauncher.start();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AIServer starting — tap Connect once ready.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // android_intent_plus throws ActivityNotFoundException when the
        // AIServerAndroid package is not installed on this device.
        final msg = e.toString().contains('ActivityNotFoundException') ||
                e.toString().contains('No Activity found')
            ? 'AIServerAndroid is not installed on this device.'
            : 'Could not start AIServer. Is AIServerAndroid installed?';
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  // ── Stop server ────────────────────────────────────────────────────────────

  /// Stops the server companion app and frees model memory.
  ///
  /// Stop sequence (critical for memory):
  ///   1. HTTP POST /v1/models/unload — frees the native model allocation while
  ///      the server is still reachable.
  ///   2. Platform signal (Android intent / iOS URL scheme) — terminates the
  ///      server process so the OS can reclaim all remaining memory.
  Future<void> _stopServer() async {
    setState(() {
      _stopping = true;
      _error = null;
    });
    try {
      // Step 1: unload model via HTTP (best-effort — server may already be down).
      if (ApiService.isConfigured) {
        try {
          await ApiService.instance
              .unloadModel()
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // Ignore — server may be unreachable; proceed with platform stop.
        }
      }
      // Step 2: send the platform stop signal.
      await ServerLauncher.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server stopped — model memory freed.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not stop server: $e');
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Invalid port number');
      return;
    }

    final host = _hostCtrl.text.trim();
    final testUri = Uri.tryParse('http://$host:$port');
    if (testUri == null || testUri.host.isEmpty) {
      setState(() => _error = 'Invalid host address');
      return;
    }

    final config = ServerConfig(host: host, port: port);

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      // Configure the singleton before checking health.
      ApiService.configure(config);
      final health = await ApiService.instance.checkHealth();

      if (!mounted) return;

      if (!health.ok) {
        setState(() => _error = health.error);
        return;
      }

      // Persist connection details on success.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_host', config.host);
      await prefs.setInt('server_port', config.port);

      if (!mounted) return;

      if (health.modelLoaded) {
        // Model is ready — go straight to chat.
        final connectedConfig = config.copyWith(modelId: health.modelId);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChatScreen(config: connectedConfig),
          ),
        );
      } else {
        // Server is up but no model loaded — open the model catalog.
        final loadedModelId = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const ModelCatalogScreen()),
        );
        if (!mounted) return;
        if (loadedModelId != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                config: config.copyWith(modelId: loadedModelId),
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                'Gemma 4 Chat',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to the Gemma 4 inference server running on this device.',
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 40),

              // ── Server controls (Android + iOS) ────────────────────────────
              if (!kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS)) ...[
                Text(
                  'Server',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Start button
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed:
                              (_launching || _stopping || _checking)
                                  ? null
                                  : _launchServer,
                          icon: _launching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.rocket_launch_outlined),
                          label: const Text('Start'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Stop button (destructive style)
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed:
                              (_stopping || _launching || _checking)
                                  ? null
                                  : _stopServer,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(
                                color: _stopping
                                    ? theme.colorScheme.outline
                                    : theme.colorScheme.error),
                          ),
                          icon: _stopping
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              : const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],

              // ── Address fields ─────────────────────────────────────────────
              Text(
                'Server Address',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        border: OutlineInputBorder(),
                        hintText: '127.0.0.1',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                        hintText: '8080',
                      ),
                    ),
                  ),
                ],
              ),

              // ── Error banner ───────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Connect button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _checking ? null : _connect,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
              ),
              const SizedBox(height: 32),

              // ── Quick-start hint ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Start',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (!kIsWeb &&
                              defaultTargetPlatform == TargetPlatform.android)
                          ? '1. Tap Start above to launch AIServerAndroid.\n'
                              '2. Tap Connect → choose a Gemma 4 model.\n'
                              '3. Download, load, and start chatting.\n'
                              '4. Tap Stop when finished to free memory.\n'
                              '   (No Hugging Face token required.)'
                          : (!kIsWeb &&
                                  defaultTargetPlatform == TargetPlatform.iOS)
                              ? '1. Tap Start above to launch AIServeriOS.\n'
                                  '2. Tap Connect → choose a Gemma 4 model.\n'
                                  '3. Download, load, and start chatting.\n'
                                  '4. Tap Stop when finished to free memory.'
                              : '1. Launch AIServer on the same device.\n'
                                  '2. Complete model setup and wait for '
                                  '"Server running".\n'
                                  '3. Enter the same port here and tap Connect.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
