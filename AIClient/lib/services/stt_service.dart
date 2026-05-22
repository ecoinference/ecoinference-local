import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Singleton wrapper around [SpeechToText].
///
/// Usage:
/// ```dart
/// final ok = await SttService.instance.initialize();
/// if (ok) {
///   SttService.instance.listen(onResult: (text, final) { … });
/// }
/// ```
class SttService {
  SttService._();
  static final instance = SttService._();

  final _stt = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  bool get isListening => _listening;

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Requests microphone permission and initialises the STT engine.
  /// Returns `true` if available and permission was granted.
  Future<bool> initialize() async {
    if (_initialized) return _stt.isAvailable;
    _initialized = await _stt.initialize(
      onError: (_) => _listening = false,
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          _listening = false;
        }
      },
    );
    return _initialized && _stt.isAvailable;
  }

  // ── Listen ──────────────────────────────────────────────────────────────────

  /// Starts listening. [onResult] is called with (transcript, isFinal) on each
  /// recognition event. [onListeningChanged] fires whenever [isListening] flips.
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    void Function(bool listening)? onListeningChanged,
  }) async {
    if (_listening) return;
    final available = await initialize();
    if (!available) return;

    _listening = true;
    onListeningChanged?.call(true);

    await _stt.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          _listening = false;
          onListeningChanged?.call(false);
        }
      },
    );
  }

  // ── Stop ────────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    if (!_listening) return;
    await _stt.stop();
    _listening = false;
  }

  Future<void> cancel() async {
    if (!_listening) return;
    await _stt.cancel();
    _listening = false;
  }
}
