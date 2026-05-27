package ai.ecoinference.app.tools

/**
 * Describes a single agentic tool the model may call.
 * Mirrors iOS ToolDefinition.swift.
 *
 * [execute] returns a [ToolResult]:
 *  - [ToolResult.Text]  → JSON/string the model reads in <tool_result>.
 *  - [ToolResult.Image] → PNG bytes forwarded to the UI; caption goes to model.
 */
data class ToolDefinition(
    val name:          String,
    val description:   String,
    val parametersDoc: String,
    val argsExample:   String,
    val execute:       suspend (args: String) -> ToolResult,
)
