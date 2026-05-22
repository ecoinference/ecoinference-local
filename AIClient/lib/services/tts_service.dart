import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton wrapper around [FlutterTts].
///
/// Provides auto-read for assistant responses with a persistent on/off
/// preference stored in SharedPreferences.
class TtsService {
  TtsService._();
  static final instance = TtsService._();

  final _tts = FlutterTts();
  bool _ready = false;

  static const _kEnabledKey = 'tts_enabled';

  // ── Initialisation ──────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.52); // slightly slower than default for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // Stop speaking when app is backgrounded or the user starts a new message.
    await _tts.awaitSpeakCompletion(false);
    _ready = true;
  }

  // ── Playback ────────────────────────────────────────────────────────────────

  /// Speaks [text] after stripping markdown and tool artefacts.
  Future<void> speak(String text) async {
    await initialize();
    final clean = _stripMarkdown(text);
    if (clean.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(clean);
  }

  Future<void> stop() async {
    if (!_ready) return;
    await _tts.stop();
  }

  // ── Preference ──────────────────────────────────────────────────────────────

  /// Returns the persisted enabled state (default: false).
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  /// Persists the enabled state.
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
  }

  // ── Markdown stripper ───────────────────────────────────────────────────────

  /// Removes common markdown/code artefacts before speaking so the TTS engine
  /// doesn't read out asterisks, pound signs, backticks, etc.
  static String _stripMarkdown(String text) => text
      // Code fences (``` … ```)
      .replaceAll(RegExp(r'```[\s\S]*?```'), 'code block.')
      // Inline code (`…`)
      .replaceAll(RegExp(r'`[^`]+`'), '')
      // Bold/italic markers (**text** / *text* / __text__ / _text_)
      .replaceAll(RegExp(r'\*{1,3}|_{1,3}'), '')
      // ATX headings (# ## ###)
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      // Markdown links [label](url) → label
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      // Bare URLs
      .replaceAll(RegExp(r'https?://\S+'), 'link.')
      // HTML tags
      .replaceAll(RegExp(r'<[^>]+>'), '')
      // Bullet/numbered list markers at line start
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
      // Horizontal rules
      .replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '')
      // Collapse excessive whitespace
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
