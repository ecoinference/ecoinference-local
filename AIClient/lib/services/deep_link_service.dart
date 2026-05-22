import 'dart:async';
import 'package:app_links/app_links.dart';

/// Payload decoded from an `aiclient://` URL.
///
/// Supported URL format:
/// ```
/// aiclient://chat?message=Hello+World&send=true&system=You+are+a+coder
/// ```
/// All parameters are optional.
class DeepLinkPayload {
  const DeepLinkPayload({
    this.message,
    this.autoSend = false,
    this.system,
  });

  /// Pre-fill the chat input field with this text.
  final String? message;

  /// If true, send [message] immediately without user confirmation.
  final bool autoSend;

  /// Override the system prompt for this session.
  final String? system;

  static DeepLinkPayload? _fromUri(Uri uri) {
    if (uri.scheme != 'aiclient') return null;
    if (uri.host != 'chat') return null;

    final msg    = uri.queryParameters['message'];
    final send   = uri.queryParameters['send']?.toLowerCase() == 'true';
    final system = uri.queryParameters['system'];

    if (msg == null && system == null) return null;
    return DeepLinkPayload(message: msg, autoSend: send, system: system);
  }
}

/// Handles incoming `aiclient://` deep links on both iOS and Android.
///
/// Initialise once in [main] before [runApp]:
/// ```dart
/// await DeepLinkService.init();
/// runApp(const App());
/// ```
///
/// [ChatScreen] should:
/// 1. Call [consumePending] in [initState] to handle cold-start links.
/// 2. Subscribe to [payloadStream] to handle warm-start links.
class DeepLinkService {
  DeepLinkService._();

  static final _controller =
      StreamController<DeepLinkPayload>.broadcast();

  /// Stream of incoming deep link payloads while the app is already running.
  static Stream<DeepLinkPayload> get payloadStream => _controller.stream;

  static DeepLinkPayload? _pending;

  /// Returns (and clears) a payload delivered during cold-start, or null.
  static DeepLinkPayload? consumePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  // ── Initialisation ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    final appLinks = AppLinks();

    // Cold-start: app was launched via an aiclient:// URL.
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        final payload = DeepLinkPayload._fromUri(initialUri);
        if (payload != null) _pending = payload;
      }
    } catch (_) {
      // Not launched via link — safe to ignore.
    }

    // Warm-start: app already running when the link is tapped.
    appLinks.uriLinkStream.listen((uri) {
      final payload = DeepLinkPayload._fromUri(uri);
      if (payload != null) _controller.add(payload);
    });
  }
}
