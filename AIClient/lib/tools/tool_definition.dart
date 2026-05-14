import 'tool_result.dart';

/// Signature for a tool's execution function.
typedef ToolExecuteFn = Future<ToolResult> Function(Map<String, dynamic> args);

/// Describes a single agentic tool: its name, how the LLM should call it,
/// and the Flutter-side function that executes it.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parametersDoc,
    required this.argsExample,
    required this.execute,
    this.requiresConfirmation = false,
  });

  /// Short snake_case identifier used in <tool_call> JSON.
  final String name;

  /// One-line description shown to the LLM in the system prompt.
  final String description;

  /// Human-readable parameter list for the system prompt (e.g. "on: bool").
  final String parametersDoc;

  /// Example args JSON for the system prompt (e.g. '{"on": true}').
  final String argsExample;

  /// The Flutter function that performs the action and returns a result.
  final ToolExecuteFn execute;

  /// When true, [ChatScreen] shows a confirmation dialog before calling [execute].
  final bool requiresConfirmation;
}

// ── Registry ──────────────────────────────────────────────────────────────────

/// Central catalog of all registered agentic tools.
class ToolRegistry {
  ToolRegistry._();

  static final List<ToolDefinition> _tools = [];

  static void register(ToolDefinition tool) => _tools.add(tool);

  static List<ToolDefinition> get all => List.unmodifiable(_tools);

  static ToolDefinition? find(String name) =>
      _tools.where((t) => t.name == name).firstOrNull;

  static bool get hasTools => _tools.isNotEmpty;

  /// Returns the system-prompt block that lists every registered tool.
  /// Injected before the user's own system prompt on every inference call.
  static String buildSystemPromptBlock() {
    if (_tools.isEmpty) return '';

    final buf = StringBuffer()
      ..writeln('You have access to device hardware tools and a Python execution environment.')
      ..writeln(
          'When you need to use a tool, output EXACTLY this on its own line '
          'and nothing else — wait for the result before continuing:')
      ..writeln('<tool_call>{"name":"TOOL_NAME","args":{...}}</tool_call>')
      ..writeln()
      ..writeln('Available tools:');

    for (final t in _tools) {
      buf
        ..writeln('• ${t.name}(${t.parametersDoc}): ${t.description}')
        ..writeln(
            '  e.g. <tool_call>{"name":"${t.name}","args":${t.argsExample}}</tool_call>');
    }

    return buf.toString().trimRight();
  }
}
