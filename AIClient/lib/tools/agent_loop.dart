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
  // Gemma may close with </tool_call>, <tool_call|>, or nothing at all
  // (the closing token gets stripped server-side as an <end_of_turn> variant).
  // The closing group is therefore optional — we fall back to end-of-string.
  static final _toolCallRe = RegExp(
    r'<tool_call\s*>([\s\S]*?)(?:</tool_call>|<tool_call\|>|$)',
    dotAll: true,
  );

  /// Maximum agentic iterations before giving up and returning the raw output.
  static const maxIterations = 3;

  /// Parses [response] for a <tool_call> marker.
  /// Returns [ToolCallResult] on success, null if no valid tool call found.
  /// DEBUG: logs every step to the console.
  static ToolCallResult? parseToolCall(String response) {
    // DEBUG ─────────────────────────────────────────────────────────────────
    debugPrint('=== parseToolCall ===');
    debugPrint('response length: ${response.length}');
    debugPrint('response (first 300): ${response.substring(0, response.length.clamp(0, 300))}');
    debugPrint('contains "<tool_call>": ${response.contains("<tool_call>")}');
    debugPrint('regex pattern: ${_toolCallRe.pattern}');
    // ────────────────────────────────────────────────────────────────────────

    final match = _toolCallRe.firstMatch(response);

    // DEBUG
    debugPrint('regex match: ${match != null}');
    if (match != null) {
      debugPrint('match.start=${match.start} match.end=${match.end}');
      debugPrint('match.group(0) (first 200): ${match.group(0)?.substring(0, match.group(0)!.length.clamp(0, 200))}');
    }

    if (match == null) return null;

    var jsonStr = match.group(1)?.trim() ?? '';
    debugPrint('raw jsonStr (first 300): $jsonStr'.substring(0, 'raw jsonStr (first 300): $jsonStr'.length.clamp(0, 320)));

    // Strip markdown code fences the model sometimes wraps around the JSON.
    jsonStr = jsonStr
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: false), '')
        .replaceAll(RegExp(r'\s*```$', multiLine: false), '')
        .trim();
    debugPrint('jsonStr after fence-strip: $jsonStr'.substring(0, 'jsonStr after fence-strip: $jsonStr'.length.clamp(0, 320)));

    Map<String, dynamic>? data;

    // Attempt 1: parse as-is.
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
      debugPrint('JSON parse attempt 1: SUCCESS');
    } catch (e1) {
      debugPrint('JSON parse attempt 1 FAILED: $e1');
      // Attempt 2: escape literal control characters inside JSON string values.
      final fixed = _escapeControlCharsInStrings(jsonStr);
      debugPrint('fixed jsonStr (first 300): $fixed'.substring(0, 'fixed jsonStr (first 300): $fixed'.length.clamp(0, 320)));
      try {
        data = jsonDecode(fixed) as Map<String, dynamic>;
        debugPrint('JSON parse attempt 2: SUCCESS');
      } catch (e2) {
        debugPrint('JSON parse attempt 2 FAILED: $e2');
        // Malformed JSON — treat whole response as plain text.
        return null;
      }
    }

    debugPrint('parsed keys: ${data.keys.toList()}');
    final name = data['name'] as String? ?? '';
    // Gemma's native format uses "arguments"; our prompt uses "args" — accept both.
    final args = (data['args'] as Map<String, dynamic>?)
        ?? (data['arguments'] as Map<String, dynamic>?)
        ?? {};
    debugPrint('tool name: "$name"  args keys: ${args.keys.toList()}');

    if (name.isEmpty) {
      debugPrint('name is empty — returning null');
      return null;
    }

    debugPrint('parseToolCall SUCCESS → $name');
    return ToolCallResult(
      textBefore: response.substring(0, match.start).trim(),
      toolName: name,
      args: args,
    );
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
