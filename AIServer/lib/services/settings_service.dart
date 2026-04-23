import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Thin wrapper around SharedPreferences for app-wide settings.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Port ────────────────────────────────────────────────────────────────────

  int get port => _prefs.getInt(AppConstants.settingsKeyPort) ?? AppConstants.defaultPort;

  Future<void> setPort(int value) =>
      _prefs.setInt(AppConstants.settingsKeyPort, value);

  // ── Kaggle credentials ──────────────────────────────────────────────────────

  String get kaggleUsername =>
      _prefs.getString(AppConstants.settingsKeyKaggleUsername) ?? '';

  String get kaggleKey =>
      _prefs.getString(AppConstants.settingsKeyKaggleKey) ?? '';

  Future<void> setKaggleCredentials(String username, String key) async {
    await _prefs.setString(AppConstants.settingsKeyKaggleUsername, username);
    await _prefs.setString(AppConstants.settingsKeyKaggleKey, key);
  }

  bool get hasKaggleCredentials =>
      kaggleUsername.isNotEmpty && kaggleKey.isNotEmpty;

  // ── Selected model ──────────────────────────────────────────────────────────

  String? get selectedModelId =>
      _prefs.getString(AppConstants.settingsKeySelectedModel);

  Future<void> setSelectedModelId(String id) =>
      _prefs.setString(AppConstants.settingsKeySelectedModel, id);

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
