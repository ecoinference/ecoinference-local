package ai.ecoinference.app.tools

/**
 * Token emitted by [runAgentLoop] to the UI layer.
 *
 *  - Text:       a text chunk to stream/append to the chat bubble.
 *  - ChartImage: a PNG produced by a chart tool, shown inline below the text.
 *  - ToolText:   the raw text content returned by a text tool (e.g. run_python
 *                stdout).  The chat UI ignores this; the test runner uses it to
 *                evaluate the actual tool output rather than the model's
 *                (potentially hallucinated) summary of it — mirrors iOS behaviour.
 */
sealed class AgentToken {
    data class Text(val chunk: String)                               : AgentToken()
    data class ChartImage(val bytes: ByteArray, val caption: String) : AgentToken()
    data class ToolText(val text: String)                            : AgentToken()
}
