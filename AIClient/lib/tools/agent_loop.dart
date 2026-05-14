import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'tool_result.dart';

/// Parsed tool call extracted from an LLM response.
class ToolCallResult {
  const ToolCallResult({
    required this.textBefore,
    required this.toolName,
    required this.args,
  });

  /// Any assistant text that appeared before the <tool_call> tag.
  final String textBefore;
  final String toolName;
  final Map<String, dynamic> args;
}

/// Pure logic for the client-side agentic loop.
///
/// The UI state machine lives in [ChatScreen]; this class handles only
/// parsing and message construction so it can be tested independently.
class AgentLoop {
  // Kept only to detect presence of a tool call before attempting indexOf parse.
  static final _toolCallOpenRe = RegExp(r'<tool_call\s*>');

  /// Accumulates debug lines from the last [parseToolCall] call.
  /// Shown in the 🐛 DEBUG bubble in chat. TODO: remove before release.
  static final List<String> parseLog = [];

  /// Maximum agentic iterations before giving up and returning the raw output.
  static const maxIterations = 3;

  /// Parses [response] for a <tool_call> marker using plain indexOf —
  /// no regex on the outer structure so Dart engine quirks can't interfere.
  /// DEBUG: logs every step; TODO remove debugPrint before release.
  static ToolCallResult? parseToolCall(String response) {
    parseLog.clear();
    void log(String s) { parseLog.add(s); debugPrint('[TC] $s'); }

    log('response.length=${response.length}');

    // ── Find opening tag ────────────────────────────────────────────────────
    final openMatch = _toolCallOpenRe.firstMatch(response);
    log('openMatch=${openMatch != null}  (indexOf raw: ${response.indexOf('<tool_call')})');
    if (openMatch == null) return null;

    final contentStart = openMatch.end;
    final textBefore   = response.substring(0, openMatch.start).trim();
    log('contentStart=$contentStart');

    // ── Find closing tag ────────────────────────────────────────────────────
    const closeTags = ['</tool_call>', '<tool_call|>'];
    int contentEnd = response.length;
    String foundClose = '(none — using end-of-string)';
    for (final tag in closeTags) {
      final idx = response.indexOf(tag, contentStart);
      if (idx != -1 && idx < contentEnd) { contentEnd = idx; foundClose = tag; }
    }
    log('closeTag=$foundClose  contentEnd=$contentEnd');

    var jsonStr = response.substring(contentStart, contentEnd).trim();
    log('jsonStr.length=${jsonStr.length}');
    log('jsonStr tail (last 80): ${jsonStr.substring((jsonStr.length - 80).clamp(0, jsonStr.length))}');

    // ── Strip markdown code fences ─────────────────────────────────────────
    jsonStr = jsonStr
        .replaceAll(RegExp(r'^```(?:json)?\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    // ── Parse JSON (3 attempts) ────────────────────────────────────────────
    Map<String, dynamic>? data;

    // Attempt 1: as-is
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
      log('parse1=OK');
    } catch (e1) {
      log('parse1 FAIL: $e1');

      // Attempt 2: escape control chars in strings
      final fixed = _escapeControlCharsInStrings(jsonStr);
      try {
        data = jsonDecode(fixed) as Map<String, dynamic>;
        log('parse2=OK (after escape)');
      } catch (e2) {
        log('parse2 FAIL: $e2');

        // Attempt 3: auto-close truncated JSON (append missing '}' chars)
        final autoclosed = _autoCloseJson(fixed);
        log('autoclosed tail: ${autoclosed.substring((autoclosed.length - 40).clamp(0, autoclosed.length))}');
        try {
          data = jsonDecode(autoclosed) as Map<String, dynamic>;
          log('parse3=OK (after autoclose)');
        } catch (e3) {
          log('parse3 FAIL: $e3');
          return null;
        }
      }
    }

    log('keys=${data.keys.toList()}');
    final name = data['name'] as String? ?? '';
    final args = (data['args']       as Map<String, dynamic>?)
              ?? (data['arguments']  as Map<String, dynamic>?)
              ?? {};
    log('name="$name"  argKeys=${args.keys.toList()}');
    if (name.isEmpty) { log('name empty'); return null; }

    log('SUCCESS → $name');
    return ToolCallResult(textBefore: textBefore, toolName: name, args: args);
  }

  /// Appends missing closing braces/brackets to truncated JSON.
  static String _autoCloseJson(String s) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    for (final ch in s.runes.map(String.fromCharCode)) {
      if (escaped)       { escaped = false; continue; }
      if (ch == r'\' && inString) { escaped = true; continue; }
      if (ch == '"')     { inString = !inString; continue; }
      if (inString)      continue;
      if (ch == '{')      { stack.add('}'); }
      else if (ch == '[') { stack.add(']'); }
      else if (ch == '}' || ch == ']') {
        if (stack.isNotEmpty) stack.removeLast();
      }
    }
    return s + stack.reversed.join();
  }

  /// Scans a JSON string and escapes any literal control characters
  /// (newline, carriage return, tab) that appear inside quoted string values.
  /// This fixes the common model error of writing multi-line code directly
  /// inside a JSON string without proper `\n` escaping.
  static String _escapeControlCharsInStrings(String s) {
    final buf = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
        continue;
      }
      if (ch == r'\' && inString) {
        buf.write(ch);
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        buf.write(ch);
        continue;
      }
      if (inString) {
        switch (ch) {
          case '\n': buf.write(r'\n');
          case '\r': buf.write(r'\r');
          case '\t': buf.write(r'\t');
          default:   buf.write(ch);
        }
        continue;
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  /// Chat message shown in the UI for a completed tool call.
  static ChatMessage displayMessage(String toolName, ToolResult result) =>
      switch (result) {
        TextToolResult r => ChatMessage(
            role: MessageRole.tool, content: r.text, toolName: toolName),
        ImageToolResult r => ChatMessage(
            role: MessageRole.tool,
            content: r.caption,
            toolName: toolName,
            imageDataUrl: r.base64DataUrl),
        HtmlToolResult r => ChatMessage(
            role: MessageRole.tool,
            content: r.caption,
            toolName: toolName,
            htmlContent: r.html),
      };

  /// Builds the user-role message that feeds a tool result back to the LLM.
  /// Gemma has no native tool role, so the result is injected as a user turn.
  /// Image/HTML results send only the caption — never raw base64 or HTML.
  static ChatMessage toolResultMessage(String toolName, ToolResult result) {
    final caption = switch (result) {
      TextToolResult r => r.text,
      ImageToolResult r => r.caption,
      HtmlToolResult r => r.caption,
    };
    return ChatMessage(
      role: MessageRole.user,
      content: '[Tool result: $toolName] $caption',
    );
  }
}
