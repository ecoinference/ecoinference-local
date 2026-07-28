package ai.ecoinference.app.tools

import org.json.JSONObject

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

    /**
     * What a human-facing tool display should show. Tool error results are
     * `{"error":"..."}` JSON meant for the model to read and self-correct
     * from — showing that raw envelope to a person reads as leaked internal
     * state, not a real error message. This unwraps it into a short,
     * human-readable line; anything that isn't that exact shape (plain-text
     * fallback messages, successful results) passes through unchanged.
     */
    fun displayText(): String = humanReadable(modelText())

    companion object {
        fun humanReadable(raw: String): String {
            val message = try {
                val obj = JSONObject(raw)
                if (obj.length() == 1 && obj.has("error")) obj.getString("error") else null
            } catch (e: Exception) {
                null
            } ?: return raw

            // A Python traceback's last non-empty line is the actual exception
            // summary (e.g. "ValueError: x must be positive") — show just
            // that, not the full multi-frame trace.
            val summary = message.lines().lastOrNull { it.isNotBlank() } ?: message
            return "⚠️ $summary"
        }
    }
}
