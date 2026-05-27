package ai.ecoinference.app.tools

/**
 * The result of a tool execution.
 *
 *  - Text:  a JSON/plain-text string the model reads in <tool_result>.
 *  - Image: a rendered PNG (chart, map, etc.) plus a text caption the model
 *           reads. The PNG bytes are forwarded to the UI for inline display.
 */
sealed class ToolResult {
    data class Text(val text: String)                              : ToolResult()
    data class Image(val bytes: ByteArray, val caption: String)   : ToolResult()

    /** What the model receives inside <tool_result>. */
    fun modelText(): String = when (this) {
        is Text  -> text
        is Image -> caption
    }
}
