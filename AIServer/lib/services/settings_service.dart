import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Thin wrapper around SharedPreferences for app-wide settings.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  late SharedPreferences _prefs;

  // Dev-only: pre-populated token so setup doesn't require manual entry.
  // Remove or replace before distributing the app.
  static const String _devHfToken = 'hf_REDACTED_REVOKED_TOKEN';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Inject dev token if none is stored yet.
    if (!hasHfToken && _devHfToken.isNotEmpty) {
      await setHfToken(_devHfToken);
    }
  }

  // ── Port ────────────────────────────────────────────────────────────────────

  int get port => _prefs.getInt(AppConstants.settingsKeyPort) ?? AppConstants.defaultPort;

  Future<void> setPort(int value) =>
      _prefs.setInt(AppConstants.settingsKeyPort, value);

  // ── HuggingFace token ───────────────────────────────────────────────────────

  String get hfToken =>
      _prefs.getString(AppConstants.settingsKeyHfToken) ?? '';

  Future<void> setHfToken(String token) =>
      _prefs.setString(AppConstants.settingsKeyHfToken, token.trim());

  bool get hasHfToken => hfToken.isNotEmpty;

  // ── Selected model ──────────────────────────────────────────────────────────

  String? get selectedModelId =>
      _prefs.getString(AppConstants.settingsKeySelectedModel);

  Future<void> setSelectedModelId(String id) =>
      _prefs.setString(AppConstants.settingsKeySelectedModel, id);

  // ── Inference backend ───────────────────────────────────────────────────────

  /// When true, passes [PreferredBackend.gpu] to [FlutterGemma.getActiveModel].
  /// Defaults to false (auto / let flutter_gemma decide).
  bool get useGpu =>
      _prefs.getBool(AppConstants.settingsKeyUseGpu) ?? false;

  Future<void> setUseGpu(bool value) =>
      _prefs.setBool(AppConstants.settingsKeyUseGpu, value);

  // ── Setup state ─────────────────────────────────────────────────────────────

  bool get setupDone =>
      _prefs.getBool(AppConstants.settingsKeySetupDone) ?? false;

  Future<void> markSetupDone() =>
      _prefs.setBool(AppConstants.settingsKeySetupDone, true);

  Future<void> resetSetup() async {
    await _prefs.remove(AppConstants.settingsKeySetupDone);
    await _prefs.remove(AppConstants.settingsKeySelectedModel);
  }
}
