import Foundation

// MARK: - ToolDefinition

/// Describes a single agentic tool: how the LLM calls it and how the app
/// executes it. Mirrors Flutter's ToolDefinition class.
struct ToolDefinition {
    /// Short snake_case identifier used in <tool_call> JSON.
    let name:            String
    /// One-line description shown to the LLM in the system prompt.
    let description:     String
    /// Human-readable parameter list, e.g. "(no parameters)".
    let parametersDoc:   String
    /// Example args JSON for the system prompt, e.g. "{}".
    let argsExample:     String
    /// The app-side function that performs the action and returns a result string.
    let execute:         ([String: Any]) async -> String
}

// MARK: - ToolRegistry

/// Central catalog of all registered agentic tools.
/// Provides the system-prompt block that tells the LLM what tools it has.
final class ToolRegistry {

    static let shared = ToolRegistry()
    private init() {}

    private var tools: [ToolDefinition] = []

    // ── Registration ──────────────────────────────────────────────────────────

    /// Registers a tool. If a tool with the same name already exists it is
    /// replaced, so calling this from an init method is idempotent.
    func register(_ tool: ToolDefinition) {
        if let idx = tools.firstIndex(where: { $0.name == tool.name }) {
            tools[idx] = tool
        } else {
            tools.append(tool)
        }
    }

    var all:        [ToolDefinition] { tools }
    var hasTools:   Bool             { !tools.isEmpty }

    func find(_ name: String) -> ToolDefinition? {
        tools.first { $0.name == name }
    }

    // ── System-prompt block ───────────────────────────────────────────────────

    /// Returns the block injected at the start of every system prompt so the
    /// LLM knows which tools are available and how to call them.
    func buildSystemPromptBlock() -> String {
        guard !tools.isEmpty else { return "" }

        var buf = """
You have access to device hardware tools.
When you need to use a tool, output EXACTLY one line in this format and nothing else — then wait for the result before continuing:
<tool_call>{"name":"TOOL_NAME","args":{...}}</tool_call>
IMPORTANT: The entire tool_call must be valid JSON on a single line. \
Do NOT use actual newlines inside the tool_call tags.

Available tools:
"""
        for t in tools {
            buf += "\n• \(t.name)(\(t.parametersDoc)): \(t.description)"
            buf += "\n  e.g. <tool_call>{\"name\":\"\(t.name)\",\"args\":\(t.argsExample)}</tool_call>"
        }
        return buf
    }
}
