import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Starts and stops the AI Server companion app.
///
/// - Android: sends an explicit Intent to AIServerAndroid's trampoline Activity.
/// - iOS: launches AIServeriOS via the `aiserver://` URL scheme.
/// - Other platforms: no-op.
class ServerLauncher {
  ServerLauncher._();

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // ── Android constants ─────────────────────────────────────────────────────

  static const _package           = 'com.gemma4.aiserver';
  static const _actionStart       = 'com.gemma4.aiserver.ACTION_START';
  static const _actionStop        = 'com.gemma4.aiserver.ACTION_STOP';
  static const _activityComponent = 'com.gemma4.aiserver.StartServerActivity';

  // ── iOS URL scheme ────────────────────────────────────────────────────────

  static final _iosStart = Uri.parse('aiserver://start');
  static final _iosStop  = Uri.parse('aiserver://stop');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start the server companion app.
  static Future<void> start() async {
    if (_isAndroid) {
      await _androidLaunch(_actionStart);
    } else if (_isIOS) {
      await _iosLaunch(_iosStart);
    }
  }

  /// Stop the server companion app.
  static Future<void> stop() async {
    if (_isAndroid) {
      await _androidLaunch(_actionStop);
    } else if (_isIOS) {
      await _iosLaunch(_iosStop);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _androidLaunch(String action) async {
    final intent = AndroidIntent(
      action: action,
      package: _package,
      componentName: _activityComponent,
      // FLAG_INCLUDE_STOPPED_PACKAGES wakes the app even if it has never
      // been opened. FLAG_ACTIVITY_NEW_TASK is required when starting an
      // Activity from a non-Activity context.
      flags: [
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_INCLUDE_STOPPED_PACKAGES,
      ],
    );
    await intent.launch();
  }

  static Future<void> _iosLaunch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
    // If AIServeriOS is not installed, silently ignore — caller can handle.
  }
}
