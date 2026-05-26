package ai.ecoinference.app.tools

/**
 * Central registry for agentic tools.
 * Mirrors iOS ToolRegistry.swift.
 */
object ToolRegistry {

    private val tools = mutableMapOf<String, ToolDefinition>()

    fun register(tool: ToolDefinition) { tools[tool.name] = tool }

    fun find(name: String): ToolDefinition? = tools[name]

    fun all(): List<ToolDefinition> = tools.values.toList()

    /**
     * Builds the system-prompt block that tells the model which tools are
     * available and how to call them.
     */
    fun systemPromptBlock(): String {
        if (tools.isEmpty()) return ""
        return buildString {
            appendLine("You have access to the following tools. To call a tool, reply with:")
            appendLine("<tool_call>{\"name\":\"<tool_name>\",\"args\":{...}}</tool_call>")
            appendLine("Wait for a <tool_result> before continuing.")
            appendLine()
            appendLine("Available tools:")
            for (t in tools.values) {
                appendLine("- **${t.name}**: ${t.description}")
                if (t.parametersDoc.isNotBlank()) appendLine("  Parameters: ${t.parametersDoc}")
                appendLine("  Example: ${t.argsExample}")
            }
        }
    }
}
