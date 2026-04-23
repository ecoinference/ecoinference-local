import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../services/settings_service.dart';

/// Server settings: port number and Kaggle credentials.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _portCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _keyVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _portCtrl.text = s.port.toString();
    _usernameCtrl.text = s.kaggleUsername;
    _keyCtrl.text = s.kaggleKey;
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final portVal = int.tryParse(_portCtrl.text.trim());
    if (portVal == null || portVal < 1024 || portVal > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be between 1024 and 65535')),
      );
      return;
    }

    setState(() => _saving = true);
    final s = SettingsService.instance;
    await s.setPort(portVal);
    await s.setKaggleCredentials(
      _usernameCtrl.text.trim(),
      _keyCtrl.text.trim(),
    );
    setState(() => _saving = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved. Server will restart.'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _resetSetup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Setup'),
        content: const Text(
            'This will clear the selected model and return to the setup '
            'screen on next launch. Downloaded files are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SettingsService.instance.resetSetup();
    Navigator.of(context).pushNamedAndRemoveUntil('/setup', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Server section ───────────────────────────────────────────────
          _SectionHeader(title: 'Server'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Port',
                      border: const OutlineInputBorder(),
                      helperText:
                          'Default: ${AppConstants.defaultPort}. Range: 1024–65535.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Kaggle section ───────────────────────────────────────────────
          _SectionHeader(title: 'Kaggle Credentials'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _keyCtrl,
                    obscureText: !_keyVisible,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_keyVisible
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _keyVisible = !_keyVisible),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Danger zone ──────────────────────────────────────────────────
          _SectionHeader(title: 'Danger Zone'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: _resetSetup,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset Setup'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
