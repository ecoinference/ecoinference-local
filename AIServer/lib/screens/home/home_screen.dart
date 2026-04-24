import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/model_catalog.dart';
import '../../services/inference_service.dart';
import '../../services/server_service.dart';
import '../../services/settings_service.dart';
import '../../services/download_service.dart';
import '../settings/settings_screen.dart';

// ── Boot step model ───────────────────────────────────────────────────────────

enum _StepState { pending, active, done, error }

class _BootStep {
  _BootStep(this.label);
  final String label;
  _StepState state = _StepState.pending;
  String? detail;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Boot steps shown during loading
  late final List<_BootStep> _steps = [
    _BootStep('Locating model file'),
    _BootStep('Loading model into memory'),
    _BootStep('Starting REST server'),
  ];

  bool _booting = true;
  bool _serverRunning = false;
  String? _error;
  String? _modelId;

  // Pulse animation for the "running" indicator
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);
  late final Animation<double> _pulseAnim =
      Tween<double>(begin: 0.4, end: 1.0).animate(
    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
  );

  // Quick-test panel
  final _testCtrl = TextEditingController();
  String? _testResult;
  bool _testRunning = false;
  StreamSubscription<String>? _testSub;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _testSub?.cancel();
    _pulseCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  // ── Boot sequence ───────────────────────────────────────────────────────────

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _error = null;
      for (final s in _steps) {
        s.state = _StepState.pending;
        s.detail = null;
      }
    });

    _modelId = SettingsService.instance.selectedModelId;

    // Step 0 — locate model
    _setStep(0, _StepState.active);
    final model = _modelId != null ? ModelCatalog.findById(_modelId!) : null;
    if (model == null) {
      // Stale or missing model ID (e.g. catalog changed, fresh install).
      // Clear setup state and send the user back to pick a model.
      await SettingsService.instance.resetSetup();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/setup', (_) => false);
      return;
    }
    final modelPath = await DownloadService.instance.modelFilePath(model);
    _setStep(0, _StepState.done, model.displayName);

    // Step 1 — load model (two phases: register file, then warm-up engine)
    _setStep(1, _StepState.active, 'Preparing…');
    try {
      await InferenceService.instance.loadModel(
        modelPath,
        _modelId!,
        onProgress: (p) {
          if (!mounted) return;
          _setStep(
            1,
            _StepState.active,
            p < 50
                ? 'Registering model file…'
                : p < 100
                    ? 'Loading weights into memory… ($p%)'
                    : 'Finalising…',
          );
        },
      );
      _setStep(1, _StepState.done, 'Model ready');
    } catch (e) {
      _setStep(1, _StepState.error, e.toString());
      setState(() { _booting = false; _error = e.toString(); });
      return;
    }

    // Step 2 — start server
    _setStep(2, _StepState.active);
    try {
      await ServerService.instance.start();
      _setStep(2, _StepState.done,
          'Listening on port ${SettingsService.instance.port}');
    } catch (e) {
      _setStep(2, _StepState.error, e.toString());
      setState(() { _booting = false; _error = e.toString(); });
      return;
    }

    setState(() {
      _booting = false;
      _serverRunning = true;
    });
  }

  void _setStep(int index, _StepState state, [String? detail]) {
    setState(() {
      _steps[index].state = state;
      _steps[index].detail = detail;
    });
  }

  // ── Quick test inference ────────────────────────────────────────────────────

  void _runTest() {
    final prompt = _testCtrl.text.trim();
    if (prompt.isEmpty || _testRunning) return;
    setState(() { _testRunning = true; _testResult = ''; });

    _testSub = InferenceService.instance
        .runChatInferenceStream(
          [{'role': 'user', 'content': prompt}],
          maxTokens: 256,
        )
        .listen(
          (token) {
            if (mounted) setState(() => _testResult = (_testResult ?? '') + token);
          },
          onError: (Object e) {
            if (mounted) setState(() {
              _testResult = '⚠️ ${e.toString()}';
              _testRunning = false;
            });
          },
          onDone: () {
            if (mounted) setState(() => _testRunning = false);
          },
        );
  }

  void _stopTest() {
    _testSub?.cancel();
    _testSub = null;
    if (mounted) setState(() => _testRunning = false);
  }

  // ── Server toggle ───────────────────────────────────────────────────────────

  Future<void> _toggleServer() async {
    if (_serverRunning) {
      await ServerService.instance.stop();
      setState(() => _serverRunning = false);
    } else {
      try {
        await ServerService.instance.start();
        setState(() => _serverRunning = true);
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (ServerService.instance.isRunning) {
                await ServerService.instance.stop();
                await ServerService.instance.start();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _booting
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildRunning(),
      ),
    );
  }

  // ── Loading view ────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Starting up…',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Loading your Gemma 4 model and starting the server.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 36),
          ..._steps.map((step) => _StepTile(step: step)),
        ],
      ),
    );
  }

  // ── Error view ──────────────────────────────────────────────────────────────

  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 72, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Start-up failed',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 32),
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

  // ── Running view ────────────────────────────────────────────────────────────

  Widget _buildRunning() {
    final theme = Theme.of(context);
    final port = SettingsService.instance.port;
    final endpoint = 'http://127.0.0.1:$port';
    final modelInfo = _modelId != null ? ModelCatalog.findById(_modelId!) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Status banner ─────────────────────────────────────────────────
          _StatusBanner(
            isRunning: _serverRunning,
            pulseAnim: _pulseAnim,
            onToggle: _toggleServer,
          ),
          const SizedBox(height: 16),

          // ── Info cards ────────────────────────────────────────────────────
          _InfoCard(
            icon: Icons.link_rounded,
            label: 'Base URL',
            value: endpoint,
            copyable: true,
          ),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.memory_rounded,
            label: 'Model',
            value: modelInfo?.displayName ?? _modelId ?? '—',
          ),
          const SizedBox(height: 20),

          // ── Endpoint list ─────────────────────────────────────────────────
          Text('Endpoints',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _EndpointList(baseUrl: endpoint),
          const SizedBox(height: 28),

          // ── Quick test ────────────────────────────────────────────────────
          Text('Quick Test',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testCtrl,
                  enabled: _serverRunning,
                  decoration: const InputDecoration(
                    hintText: 'Send a test prompt…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _runTest(),
                ),
              ),
              const SizedBox(width: 8),
              _testRunning
                  ? FilledButton.icon(
                      onPressed: _stopTest,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.error,
                      ),
                    )
                  : FilledButton(
                      onPressed: _serverRunning ? _runTest : null,
                      child: const Text('Send'),
                    ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SelectableText(
                _testResult!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});
  final _BootStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = step.state == _StepState.pending;
    final isActive  = step.state == _StepState.active;
    final isDone    = step.state == _StepState.done;
    final isError   = step.state == _StepState.error;

    final iconColor = isError
        ? theme.colorScheme.error
        : isDone
            ? Colors.green.shade600
            : isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant;

    final leading = isActive
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary),
          )
        : Icon(
            isError
                ? Icons.cancel_rounded
                : isDone
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
            color: iconColor,
            size: 22,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: isActive || isDone
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isPending
                          ? theme.colorScheme.outlineVariant
                          : null,
                    )),
                if (step.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(step.detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: isError
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.isRunning,
    required this.pulseAnim,
    required this.onToggle,
  });

  final bool isRunning;
  final Animation<double> pulseAnim;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isRunning
              ? Colors.green.shade200
              : theme.colorScheme.outlineVariant,
        ),
      ),
      color: isRunning ? Colors.green.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: pulseAnim,
              builder: (_, __) => Opacity(
                opacity: isRunning ? pulseAnim.value : 0.3,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isRunning
                        ? Colors.green.shade600
                        : theme.colorScheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isRunning ? 'Server is running' : 'Server stopped',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isRunning ? Colors.green.shade800 : null,
                ),
              ),
            ),
            Switch(
              value: isRunning,
              onChanged: (_) => onToggle(),
              activeColor: Colors.green.shade600,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        subtitle: Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        trailing: copyable
            ? IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Copied'),
                        duration: Duration(seconds: 1)),
                  );
                },
              )
            : null,
        dense: true,
      ),
    );
  }
}

class _EndpointList extends StatelessWidget {
  const _EndpointList({required this.baseUrl});
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      ('GET',  '$baseUrl/health'),
      ('GET',  '$baseUrl/v1/models'),
      ('POST', '$baseUrl/v1/models/load'),
      ('POST', '$baseUrl/v1/chat/completions'),
      ('POST', '$baseUrl/v1/completions'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: entries.indexed.map(((int, (String, String)) item) {
          final i = item.$1;
          final method = item.$2.$1;
          final path = item.$2.$2;
          final isLast = i == entries.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: method == 'GET'
                            ? Colors.blue.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(method,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: method == 'GET'
                                ? Colors.blue.shade700
                                : Colors.orange.shade700,
                          )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(path,
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant),
            ],
          );
        }).toList(),
      ),
    );
  }
}
