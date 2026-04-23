import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import 'model_picker_screen.dart';

/// Welcome / Kaggle credentials entry screen — first screen in setup flow.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _keyVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _usernameCtrl.text = s.kaggleUsername;
    _keyCtrl.text = s.kaggleKey;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await SettingsService.instance.setKaggleCredentials(
      _usernameCtrl.text.trim(),
      _keyCtrl.text.trim(),
    );
    setState(() => _saving = false);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ModelPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Icon(Icons.hub_rounded,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text('Gemma 4 Server',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Run a Gemma 4 model entirely on this device and expose '
                  'a local REST API for any client app.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 40),
                Text('Kaggle Credentials',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Models are downloaded from Kaggle. Enter your username '
                  'and API key from kaggle.com → Account → API.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kaggle Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _keyCtrl,
                  obscureText: !_keyVisible,
                  decoration: InputDecoration(
                    labelText: 'Kaggle API Key',
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _next,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Choose Model'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
