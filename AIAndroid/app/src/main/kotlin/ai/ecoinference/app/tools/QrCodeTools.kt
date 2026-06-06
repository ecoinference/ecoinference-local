package ai.ecoinference.app.tools

import android.util.Base64
import android.util.Log
import com.chaquo.python.Python

private const val TAG = "QrCodeTools"

/**
 * Registers the `generate_qr` tool.
 *
 * Generates a QR code PNG using the `qrcode` library (bundled via Chaquopy).
 * Supports any text payload: URLs, plain text, WiFi credentials, vCard contacts.
 *
 * Call [register] once from [ai.ecoinference.app.EcoInferenceApp.onCreate].
 */
object QrCodeTools {

    fun register() {
        ToolRegistry.register(ToolDefinition(
            name          = "generate_qr",
            description   = "Generates a QR code PNG image from any text, URL, WiFi credentials, " +
                "or vCard contact info. Returns an inline image. " +
                "WiFi format: WIFI:S:<SSID>;T:<WPA|WEP|nopass>;P:<password>;; " +
                "vCard format: BEGIN:VCARD\\nFN:Name\\nTEL:+1234567890\\nEND:VCARD " +
                "URL format: just pass the full URL. " +
                "box_size controls pixel size per module (1–20, default 10). " +
                "border controls quiet-zone width in modules (0–10, default 4).",
            parametersDoc = "text: string (required) — content to encode; " +
                "box_size: int (optional, default 10); border: int (optional, default 4)",
            argsExample   = """{"text":"https://ecoinference.ai"}""",
            execute       = { args ->
                val text = extractString(args, "text")
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'text' parameter is required"}""")
                val boxSize = extractInt(args, "box_size") ?: 10
                val border  = extractInt(args, "border")   ?: 4

                runCatching {
                    val py     = Python.getInstance()
                    val runner = py.getModule("runner")
                    val result = runner.callAttr("generate_qr", text, boxSize, border)

                    val parts = result.asList()
                    val type  = parts[0].toString()
                    val value = parts[1].toString()

                    Log.d(TAG, "generate_qr → type=$type text=${text.take(60)}")

                    when (type) {
                        "image" -> {
                            val bytes = Base64.decode(value, Base64.DEFAULT)
                            ToolResult.Image(bytes, "QR code for: ${text.take(60)}")
                        }
                        else -> ToolResult.Text("""{"error":"${value.replace("\"", "'")}"}""")
                    }
                }.getOrElse { e ->
                    Log.e(TAG, "generate_qr error", e)
                    ToolResult.Text("""{"error":"${e.message?.replace("\"", "'")}"}""")
                }
            }
        ))
    }

    private fun extractString(args: String, key: String): String? =
        Regex(""""$key"\s*:\s*"((?:[^"\\]|\\.)*)"""", RegexOption.DOT_MATCHES_ALL)
            .find(args)?.groupValues?.get(1)
            ?.replace("\\n", "\n")
            ?.replace("\\t", "\t")
            ?.replace("\\\"", "\"")
            ?.replace("\\\\", "\\")

    private fun extractInt(args: String, key: String): Int? =
        Regex(""""$key"\s*:\s*(\d+)""").find(args)?.groupValues?.get(1)?.toIntOrNull()
}
