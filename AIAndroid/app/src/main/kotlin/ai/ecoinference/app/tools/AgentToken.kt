package ai.ecoinference.app.tools

/**
 * Token emitted by [runAgentLoop] to the UI layer.
 *
 *  - Text:       a text chunk to stream/append to the chat bubble.
 *  - ChartImage: a PNG produced by a chart tool, shown inline below the text.
 */
sealed class AgentToken {
    data class Text(val chunk: String)                              : AgentToken()
    data class ChartImage(val bytes: ByteArray, val caption: String) : AgentToken()
}
