package ai.ecoinference.app.tools

/**
 * Describes a single agentic tool the model may call.
 * Mirrors iOS ToolDefinition.swift.
 */
data class ToolDefinition(
    val name:          String,
    val description:   String,
    val parametersDoc: String,
    val argsExample:   String,
    val execute:       suspend (args: String) -> String,
)
