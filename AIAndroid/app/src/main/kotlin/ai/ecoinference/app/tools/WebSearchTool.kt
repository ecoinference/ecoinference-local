package ai.ecoinference.app.tools

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Web search via DuckDuckGo HTML scrape.
 * Returns a plain-text summary of the top results.
 */
object WebSearchTool {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    fun register() {
        ToolRegistry.register(ToolDefinition(
            name          = "web_search",
            description   = "Searches the web and returns a plain-text summary of the top results.",
            parametersDoc = "query: string",
            argsExample   = "{\"query\":\"latest Android news\"}",
            execute       = { args ->
                val query = extractQuery(args)
                if (query.isBlank()) return@ToolDefinition "Error: 'query' is required"
                search(query)
            }
        ))
    }

    private fun extractQuery(args: String): String {
        // Simple extraction — args is a JSON object like {"query":"..."}
        val match = Regex("\"query\"\\s*:\\s*\"(.*?)\"", RegexOption.DOT_MATCHES_ALL)
            .find(args)
        return match?.groupValues?.get(1)?.trim() ?: ""
    }

    private suspend fun search(query: String): String = withContext(Dispatchers.IO) {
        try {
            val url = "https://html.duckduckgo.com/html/?q=${
                java.net.URLEncoder.encode(query, "UTF-8")
            }"
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0 (Android) EcoInference/1.0")
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext "Error: HTTP ${response.code}"
                val body = response.body?.string() ?: return@withContext "Error: empty response"
                extractResults(body)
            }
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }

    private fun extractResults(html: String): String {
        // Extract result titles and snippets from DuckDuckGo HTML
        val results = mutableListOf<String>()
        val snippetRe = Regex("<a class=\"result__snippet\"[^>]*>(.*?)</a>", RegexOption.DOT_MATCHES_ALL)
        val titleRe   = Regex("<a class=\"result__a\"[^>]*>(.*?)</a>",      RegexOption.DOT_MATCHES_ALL)

        val titles   = titleRe.findAll(html).map { stripTags(it.groupValues[1]) }.toList()
        val snippets = snippetRe.findAll(html).map { stripTags(it.groupValues[1]) }.toList()

        for (i in 0 until minOf(titles.size, snippets.size, 5)) {
            results += "${i + 1}. ${titles[i]}\n   ${snippets[i]}"
        }
        return if (results.isEmpty()) "No results found." else results.joinToString("\n\n")
    }

    private fun stripTags(html: String): String =
        html.replace(Regex("<[^>]+>"), "").replace("&amp;", "&")
            .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").trim()
}
