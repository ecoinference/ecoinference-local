import 'package:shared_preferences/shared_preferences.dart';

/// Manages the "are you sure you want to search the internet?" confirmation
/// shown before web searches.
///
/// Confirmation is shown when **either** condition is true:
///   • The search topic has changed significantly (Jaccard similarity < 0.3)
///   • More than 1 hour has passed since the user last confirmed
///
/// The user can tick "Don't ask again" to permanently suppress future
/// confirmations. This opt-out is persisted in SharedPreferences.
class SearchConfirmationService {
  SearchConfirmationService._();

  // ── SharedPreferences keys ──────────────────────────────────────────────────

  static const _kOptOut      = 'web_search_opt_out';
  static const _kLastConfirm = 'web_search_last_confirm_ms';
  static const _kLastTopic   = 'web_search_last_topic';

  // ── Tunables ────────────────────────────────────────────────────────────────

  /// Similarity threshold below which we consider the topic "changed".
  /// Jaccard similarity ∈ [0, 1]; 0.3 means <30% keyword overlap.
  static const _topicChangedThreshold = 0.3;

  /// Re-confirm after this much time even if the topic hasn't changed.
  static const _confirmInterval = Duration(hours: 1);

  // ── Dialog callback (set by ChatScreen) ────────────────────────────────────

  /// Called when a confirmation dialog needs to be shown.
  /// Returns `true` if the user allowed the search, `false` if cancelled.
  /// The bool arg `isOptOutChecked` is pre-set; the callback should honour it
  /// and pass back the user's final opt-out choice via [onOptOut].
  static Future<bool> Function(String query)? _dialogCallback;

  static void setDialogCallback(Future<bool> Function(String query) fn) {
    _dialogCallback = fn;
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns `true` when the search should proceed (either opt-out is set or
  /// the user confirmed the dialog).
  ///
  /// Persists the confirmed time + topic on approval so that subsequent
  /// searches on the same topic within the hour skip the dialog.
  static Future<bool> requestConfirmation(String query) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Permanent opt-out → always proceed without dialog.
    if (prefs.getBool(_kOptOut) ?? false) return true;

    // 2. Check whether we need to show the dialog.
    if (!_needsConfirmation(query, prefs)) {
      _updateState(query, prefs);
      return true;
    }

    // 3. Show dialog.
    final callback = _dialogCallback;
    if (callback == null) {
      // No dialog registered (shouldn't happen in production) — allow.
      return true;
    }

    final allowed = await callback(query);
    if (allowed) _updateState(query, prefs);
    return allowed;
  }

  /// Clears the permanent opt-out so confirmations resume.
  static Future<void> clearOptOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOptOut);
  }

  /// Saves the permanent opt-out preference.
  static Future<void> setOptOut(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_kOptOut, true);
    } else {
      await prefs.remove(_kOptOut);
    }
  }

  /// Whether the user has previously opted out of future confirmations.
  static Future<bool> isOptedOut() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptOut) ?? false;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static bool _needsConfirmation(String query, SharedPreferences prefs) {
    // Time check: >1 hour since last confirmation?
    final lastMs = prefs.getInt(_kLastConfirm);
    if (lastMs == null) return true; // first-ever search
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - lastMs;
    if (elapsed > _confirmInterval.inMilliseconds) return true;

    // Topic check: has the query topic changed significantly?
    final lastTopic = prefs.getString(_kLastTopic) ?? '';
    if (_topicChanged(lastTopic, query)) return true;

    return false;
  }

  static void _updateState(String query, SharedPreferences prefs) {
    prefs.setInt(_kLastConfirm, DateTime.now().millisecondsSinceEpoch);
    prefs.setString(_kLastTopic, query);
  }

  // ── Topic similarity (Jaccard on keyword sets) ──────────────────────────────

  /// Common English stopwords excluded from keyword extraction.
  static const _stopwords = {
    'a','an','the','and','or','but','in','on','at','to','for','of','with',
    'by','from','up','about','into','over','after','is','it','its','was',
    'are','be','been','being','have','has','had','do','does','did','will',
    'would','could','should','may','might','shall','can','need','must',
    'what','which','who','how','when','where','why','that','this','these',
    'those','i','me','my','we','our','you','your','he','she','his','her',
    'they','their','them','not','no','nor','so','yet','both','either',
  };

  /// Extracts a set of meaningful keywords from a query string.
  static Set<String> _keywords(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !_stopwords.contains(w))
        .toSet();
  }

  /// Jaccard similarity between two keyword sets.
  static double _similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return intersection / union;
  }

  static bool _topicChanged(String lastTopic, String newQuery) {
    final a = _keywords(lastTopic);
    final b = _keywords(newQuery);
    return _similarity(a, b) < _topicChangedThreshold;
  }
}
