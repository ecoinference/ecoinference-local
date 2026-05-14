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

  /// Maximum agentic iterations before giving up and returning the raw output.
  static const maxIterations = 3;

  /// Parses [response] for a <tool_call> marker using plain indexOf —
  /// no regex on the outer structure so Dart engine quirks can't interfere.
  /// DEBUG: logs every step; TODO remove debugPrint before release.
  static ToolCallResult? parseToolCall(String response) {
    debugPrint('=== parseToolCall ===');
    debugPrint('response length: ${response.length}');
    debugPrint('raw (first 400): ${response.substring(0, response.length.clamp(0, 400))}');

    // ── Find opening tag ────────────────────────────────────────────────────
    final openMatch = _toolCallOpenRe.firstMatch(response);
    debugPrint('open tag match: ${openMatch != null}');
    if (openMatch == null) return null;

    final contentStart = openMatch.end;           // index just after '>'
    final textBefore   = response.substring(0, openMatch.start).trim();

    // ── Find closing tag (any known variant) ───────────────────────────────
    const closeTags = ['</tool_call>', '<tool_call|>'];
    int contentEnd = response.length;             // default: rest of string
    for (final tag in closeTags) {
      final idx = response.indexOf(tag, contentStart);
      if (idx != -1 && idx < contentEnd) contentEnd = idx;
    }
    debugPrint('contentStart=$contentStart contentEnd=$contentEnd');

    var jsonStr = response.substring(contentStart, contentEnd).trim();
    debugPrint('raw jsonStr (first 400): ${jsonStr.substring(0, jsonStr.length.clamp(0, 400))}');

    // ── Strip markdown code fences ─────────────────────────────────────────
    jsonStr = jsonStr
        .replaceAll(RegExp(r'^```(?:json)?\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    // ── Parse JSON — two attempts ──────────────────────────────────────────
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
      debugPrint('JSON parse attempt 1: SUCCESS');
    } catch (e1) {
      debugPrint('JSON parse attempt 1 FAILED: $e1');
      final fixed = _escapeControlCharsInStrings(jsonStr);
      try {
        data = jsonDecode(fixed) as Map<String, dynamic>;
        debugPrint('JSON parse attempt 2 (escaped): SUCCESS');
      } catch (e2) {
        debugPrint('JSON parse attempt 2 FAILED: $e2');
        return null;
      }
    }

    debugPrint('parsed keys: ${data.keys.toList()}');
    final name = data['name'] as String? ?? '';
    final args = (data['args']       as Map<String, dynamic>?)
              ?? (data['arguments']  as Map<String, dynamic>?)
              ?? {};
    debugPrint('name="$name"  args keys: ${args.keys.toList()}');

    if (name.isEmpty) { debugPrint('name empty — null'); return null; }

    debugPrint('parseToolCall SUCCESS → $name');
    return ToolCallResult(textBefore: textBefore, toolName: name, args: args);
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
