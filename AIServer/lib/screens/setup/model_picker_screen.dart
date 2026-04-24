import 'package:flutter/material.dart';
import '../../constants/model_catalog.dart';
import '../../models/model_info.dart';
import '../../services/download_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/model_card.dart';
import 'download_screen.dart';

/// Displays the available Gemma 4 model variants and lets the user pick one.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key});

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  String? _selectedId;
  late Future<Map<String, bool>> _downloadStatusFuture;

  @override
  void initState() {
    super.initState();
    _selectedId = SettingsService.instance.selectedModelId;
    _downloadStatusFuture = _loadDownloadStatus();
  }

  Future<Map<String, bool>> _loadDownloadStatus() async {
    final result = <String, bool>{};
    for (final m in ModelCatalog.models) {
      result[m.id] = await DownloadService.instance.isDownloaded(m);
    }
    return result;
  }

  void _refresh() {
    setState(() {
      _downloadStatusFuture = _loadDownloadStatus();
    });
  }

  Future<void> _proceed(ModelInfo model, bool alreadyDownloaded) async {
    await SettingsService.instance.setSelectedModelId(model.id);
    if (!mounted) return;
    if (alreadyDownloaded) {
      // Already on disk — jump straight to home.
      await SettingsService.instance.markSetupDone();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DownloadScreen(
            model: model,
            onComplete: () async {
              await SettingsService.instance.markSetupDone();
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (_) => false);
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Model'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh download status',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, bool>>(
        future: _downloadStatusFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final status = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Select the model variant to use. Larger models produce '
                  'better output but need more RAM and take longer to download.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ModelCatalog.models.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final model = ModelCatalog.models[index];
                    final downloaded = status[model.id] ?? false;
                    return ModelCard(
                      model: model,
                      isSelected: _selectedId == model.id,
                      isDownloaded: downloaded,
                      onTap: () => setState(() => _selectedId = model.id),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 51),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _selectedId == null
                        ? null
                        : () {
                            final model = ModelCatalog.findById(_selectedId!)!;
                            _proceed(model, status[model.id] ?? false);
                          },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Continue'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
