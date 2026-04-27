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
  static const _actionStop = 'com.gemma4.aiserver.ACTION_STOP';

  /// Sends `ACTION_START` to AIServerAndroid.
  ///
  /// The OS starts the service as a foreground service; the HTTP server will
  /// be available within a second or two after this returns.
  static Future<void> start() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: _actionStart,
      package: _package,
      // FLAG_INCLUDE_STOPPED_PACKAGES allows starting even if the server app
      // has never been opened by the user.
      flags: [Flag.FLAG_INCLUDE_STOPPED_PACKAGES],
    );
    await intent.launch();
  }

  /// Sends `ACTION_STOP` to AIServerAndroid, shutting down the HTTP server.
  static Future<void> stop() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: _actionStop,
      package: _package,
      flags: [Flag.FLAG_INCLUDE_STOPPED_PACKAGES],
    );
    await intent.launch();
  }
}
