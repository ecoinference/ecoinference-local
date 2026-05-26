package ai.ecoinference.app.tools

import android.content.Context
import android.content.Intent
import android.net.Uri

object UrlTools {
    fun register(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "open_url",
            description   = "Opens a URL in the device browser.",
            parametersDoc = "url: string",
            argsExample   = "{\"url\":\"https://example.com\"}",
            execute       = { args ->
                val match = Regex("\"url\"\\s*:\\s*\"(.*?)\"").find(args)
                val url   = match?.groupValues?.get(1)?.trim() ?: ""
                if (url.isBlank()) return@ToolDefinition "Error: 'url' is required"
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    """{"opened":"$url"}"""
                } catch (e: Exception) {
                    """{"error":"${e.message}"}"""
                }
            }
        ))
    }
}
