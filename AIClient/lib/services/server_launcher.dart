import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

/// Starts and stops the AIServerAndroid foreground service via explicit Intent.
///
/// All methods are no-ops on non-Android platforms.
class ServerLauncher {
  ServerLauncher._();

  /// True only on a real Android device/emulator — safe on web and iOS.
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _package = 'com.gemma4.aiserver';
  static const _actionStart = 'com.gemma4.aiserver.ACTION_START';
  static const _actionStop  = 'com.gemma4.aiserver.ACTION_STOP';

  // Targets the transparent trampoline Activity in AIServerAndroid.
  // On Android 12+ startForegroundService() is blocked from a cross-app
  // BroadcastReceiver; an Activity being launched IS granted BFSL, so this
  // is the only reliable cross-app trigger on modern Android.
  static const _activityComponent = 'com.gemma4.aiserver.StartServerActivity';

  /// Launches the trampoline Activity in AIServerAndroid, which immediately
  /// starts AiServerService and finishes. Transparent — user sees nothing.
  static Future<void> start() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: _actionStart,
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

  /// Stops the AIServerAndroid foreground service.
  static Future<void> stop() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: _actionStop,
      package: _package,
      componentName: _activityComponent,
      flags: [
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_INCLUDE_STOPPED_PACKAGES,
      ],
    );
    await intent.launch();
  }
}
