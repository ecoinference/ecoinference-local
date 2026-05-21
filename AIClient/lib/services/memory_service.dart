import 'package:shared_preferences/shared_preferences.dart';

/// Persistent key-value memory backed by [SharedPreferences].
///
/// The LLM writes to memory by embedding XML tags anywhere in its response:
///   <mem_store key="user_name" value="Mark"/>
///   <mem_forget key="user_name"/>
///
/// [processTags] handles those writes, strips the tags from the displayed text,
/// and returns the cleaned string (or `null` if no tags were found).
/// [stripTags] removes tags without persisting anything — used during streaming
/// to keep the live bubble clean before the full response is committed.
///
/// All stored memories are injected into the system prompt via [buildContextBlock].
class MemoryService {
  MemoryService._();

  static const _prefix = 'mem_';

  // ── CRUD ──────────────────────────────────────────────────────────────────

  static Future<void> store(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  static Future<void> forget(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  static Future<Map<String, String>> listAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith(_prefix)) {
        result[k.substring(_prefix.length)] = prefs.getString(k)!;
      }
    }
    return result;
  }

  // ── System-prompt context block ───────────────────────────────────────────

  /// Returns a `[Memories]` context block ready for system prompt injection,
  /// or `null` if nothing has been stored yet.
  static Future<String?> buildContextBlock() async {
    final memories = await listAll();
    if (memories.isEmpty) return null;
    final lines =
        memories.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return '[Memories]\n$lines';
  }

  /// Constant instruction block appended to every system prompt so the model
  /// always knows how to use memory regardless of whether any entries exist.
  static const String memoryInstructions =
      '[Memory Instructions]\n'
      'You can save facts that persist between conversations.\n'
      'To save: add <mem_store key="topic" value="the fact"/> anywhere in your reply.\n'
      'To forget: add <mem_forget key="topic"/> anywhere in your reply.\n'
      'These tags are invisible to the user. Use them whenever you learn something '
      'worth remembering (user name, preferences, important facts, etc.).';

  // ── Tag parsing ───────────────────────────────────────────────────────────

  static final _storeRe = RegExp(
    r'<mem_store\s+key="([^"]+)"\s+value="([^"]+)"\s*/>',
    caseSensitive: false,
  );

  static final _forgetRe = RegExp(
    r'<mem_forget\s+key="([^"]+)"\s*/>',
    caseSensitive: false,
  );

  /// Removes all memory tags from [text] **without** persisting any changes.
  /// Called on every streaming token to keep the live bubble tag-free.
  static String stripTags(String text) => text
      .replaceAll(_storeRe, '')
      .replaceAll(_forgetRe, '')
      .trim();

  /// Processes all memory tags in [text]: stores / forgets as instructed,
  /// then returns the cleaned string with all tags removed.
  ///
  /// Returns `null` if no tags were found (the caller can skip refreshing state).
  static Future<String?> processTags(String text) async {
    bool found = false;

    for (final m in _storeRe.allMatches(text)) {
      await store(m.group(1)!, m.group(2)!);
      found = true;
    }
    for (final m in _forgetRe.allMatches(text)) {
      await forget(m.group(1)!);
      found = true;
    }

    if (!found) return null;
    return stripTags(text);
  }
}
