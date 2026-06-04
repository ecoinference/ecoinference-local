package ai.ecoinference.app.tools

import android.annotation.SuppressLint
import android.content.Context
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/**
 * Singleton that manages a hidden WebView running Pyodide (python_runner.html).
 *
 * Usage:
 *   PythonRunner.initialize(applicationContext)   ← call once in Application.onCreate()
 *   val result = PythonRunner.execute("result = 2 + 2")
 *
 * The WebView loads the asset and bootstraps Pyodide from CDN on first init.
 * Subsequent execute() calls reuse the warm Pyodide runtime — no re-init cost.
 *
 * Thread-safety: initialize() must be called from the main thread (WebView
 * creation requirement).  execute() is a suspend function safe to call from
 * any coroutine context — it marshals to Main internally.
 */
object PythonRunner {

    private var webView: WebView? = null
    private val readyDeferred  = CompletableDeferred<Unit>()
    private val scope          = MainScope()

    // One pending execution at a time (tool calls are serialised by AgentLoop).
    @Volatile private var pendingResult: CompletableDeferred<String>? = null

    // ── Initialisation ────────────────────────────────────────────────────────

    @SuppressLint("SetJavaScriptEnabled")
    fun initialize(context: Context) {
        // WebView must be created on the main thread.
        scope.launch(Dispatchers.Main) {
            val wv = WebView(context.applicationContext)
            wv.settings.javaScriptEnabled  = true
            wv.settings.domStorageEnabled  = true
            wv.settings.allowFileAccess    = true

            // Inject the Kotlin ↔ JS bridge as "AndroidBridge" global.
            wv.addJavascriptInterface(JsBridge(readyDeferred) { pendingResult?.complete(it) }, "AndroidBridge")

            wv.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    // Page loaded — Pyodide init begins; bridge fires 'ready' when done.
                }
            }

            wv.loadUrl("file:///android_asset/python_runner.html")
            webView = wv
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Execute [code] in the Pyodide runtime and return a [ToolResult].
     *
     * Waits up to 90 s total (30 s for Pyodide ready + 60 s for execution).
     * Returns [ToolResult.Image] when the code produces a matplotlib/plotly PNG
     * data-URL; [ToolResult.Text] otherwise.
     */
    suspend fun execute(code: String): ToolResult {
        // Wait for Pyodide to become ready (first call may trigger CDN load).
        try {
            withTimeout(90_000) { readyDeferred.await() }
        } catch (e: TimeoutCancellationException) {
            return ToolResult.Text("""{"error":"Pyodide failed to initialise within 90 s"}""")
        }

        val resultDeferred = CompletableDeferred<String>()
        pendingResult = resultDeferred

        // Pass code as base64 to avoid any JS string-escaping issues.
        val b64 = Base64.encodeToString(code.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)

        withContext(Dispatchers.Main) {
            webView?.evaluateJavascript("runPythonB64('$b64')", null)
        }

        val json = try {
            withTimeout(65_000) { resultDeferred.await() }
        } catch (e: TimeoutCancellationException) {
            return ToolResult.Text("""{"error":"Python execution timed out"}""")
        }

        return parseResult(json)
    }

    // ── JS → Kotlin bridge ────────────────────────────────────────────────────

    private class JsBridge(
        private val ready: CompletableDeferred<Unit>,
        private val onResult: (String) -> Unit,
    ) {
        @JavascriptInterface
        fun postMessage(json: String) {
            try {
                val type = JSONObject(json).optString("type")
                when (type) {
                    "ready"           -> ready.complete(Unit)
                    "result", "error" -> onResult(json)
                }
            } catch (_: Exception) {
                onResult("""{"type":"error","value":"Malformed bridge message"}""")
            }
        }
    }

    // ── Result parsing ────────────────────────────────────────────────────────

    private fun parseResult(json: String): ToolResult {
        return try {
            val obj   = JSONObject(json)
            val type  = obj.optString("type")
            val value = obj.optString("value", "")

            if (type == "error") {
                return ToolResult.Text("""{"error":"$value"}""")
            }

            // Matplotlib / PIL data URL → decode to PNG bytes
            if (value.startsWith("data:image/png;base64,")) {
                val b64 = value.removePrefix("data:image/png;base64,")
                val bytes = Base64.decode(b64, Base64.DEFAULT)
                return ToolResult.Image(bytes, "Python-generated plot (${bytes.size / 1024} KB PNG)")
            }

            // Plotly / folium full HTML → return as text (rendered in bubble)
            if (value.trimStart().startsWith("<!DOCTYPE") || value.trimStart().startsWith("<html")) {
                return ToolResult.Text(value)
            }

            ToolResult.Text(value)
        } catch (_: Exception) {
            ToolResult.Text("""{"error":"Could not parse Python result"}""")
        }
    }
}
