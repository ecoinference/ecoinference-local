import 'dart:convert';
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
  static final _toolCallRe = RegExp(
    r'<tool_call>(.*?)</tool_call>',
    dotAll: true,
  );

  /// Maximum agentic iterations before giving up and returning the raw output.
  static const maxIterations = 3;

  /// Parses [response] for a <tool_call> marker.
  /// Returns [ToolCallResult] on success, null if no valid tool call found.
  static ToolCallResult? parseToolCall(String response) {
    final match = _toolCallRe.firstMatch(response);
    if (match == null) return null;

    var jsonStr = match.group(1)?.trim() ?? '';

    // Strip markdown code fences the model sometimes wraps around the JSON.
    jsonStr = jsonStr
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: false), '')
        .replaceAll(RegExp(r'\s*```$', multiLine: false), '')
        .trim();

    Map<String, dynamic>? data;

    // Attempt 1: parse as-is.
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      // Attempt 2: escape literal control characters inside JSON string values.
      // Gemma often emits Python code with real newlines/tabs inside the JSON,
      // which is invalid — fix it by scanning character-by-character.
      try {
        data = jsonDecode(_escapeControlCharsInStrings(jsonStr))
            as Map<String, dynamic>;
      } catch (_) {
        // Malformed JSON — treat whole response as plain text.
        return null;
      }
    }

    final name = data['name'] as String? ?? '';
    final args = (data['args'] as Map<String, dynamic>?) ?? {};
    if (name.isEmpty) return null;

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
