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
            appendLine("You have access to tools. When you need real-time or device information, call a tool.")
            appendLine("To call a tool you MUST use this EXACT format — valid JSON only, no other syntax:")
            appendLine("<tool_call>{\"name\":\"tool_name\",\"args\":{\"param\":\"value\"}}</tool_call>")
            appendLine("After calling a tool, wait for <tool_result> before writing your final answer.")
            appendLine("Do NOT guess or make up answers that require real-time data — use a tool instead.")
            appendLine("You have a budget of $MAX_TOOL_ITERATIONS tool calls for this response — plan accordingly " +
                "and give your best answer once you've gathered what you need, rather than calling tools repeatedly.")
            appendLine()
            appendLine("Available tools:")
            for (t in tools.values) {
                appendLine("- ${t.name}: ${t.description}")
                if (t.parametersDoc.isNotBlank()) appendLine("  Parameters: ${t.parametersDoc}")
                appendLine("  Call example: <tool_call>{\"name\":\"${t.name}\",\"args\":${t.argsExample}}</tool_call>")
            }
        }
    }
}
