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

  // Targets the BroadcastReceiver in AIServerAndroid.
  // android_intent_plus only supports startActivity / sendBroadcast — it
  // cannot call startForegroundService directly. The receiver bridges the gap.
  static const _receiverComponent = 'com.gemma4.aiserver.ServerControlReceiver';

  /// Sends `ACTION_START` to AIServerAndroid via broadcast.
  ///
  /// ServerControlReceiver forwards it to AiServerService via
  /// startForegroundService. The HTTP server is ready within ~1 second.
  static Future<void> start() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: _actionStart,
      package: _package,
      componentName: _receiverComponent,
      // FLAG_INCLUDE_STOPPED_PACKAGES allows waking the app even if it has
      // never been opened by the user.
      flags: [Flag.FLAG_INCLUDE_STOPPED_PACKAGES],
    );
    await intent.sendBroadcast();
  }

  /// Sends `ACTION_STOP` to AIServerAndroid, shutting down the HTTP server.
  static Future<void> stop() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: _actionStop,
      package: _package,
      componentName: _receiverComponent,
      flags: [Flag.FLAG_INCLUDE_STOPPED_PACKAGES],
    );
    await intent.sendBroadcast();
  }
}
