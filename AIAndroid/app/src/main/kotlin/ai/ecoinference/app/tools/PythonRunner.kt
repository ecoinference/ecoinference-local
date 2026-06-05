package ai.ecoinference.app.tools

import android.util.Base64
import android.util.Log
import com.chaquo.python.Python

private const val TAG = "PythonRunner"

/**
 * Executes Python code on-device using Chaquopy (native CPython 3.11).
 *
 * Chaquopy is initialised once in EcoInferenceApp.onCreate() via
 * Python.start(AndroidPlatform(this)).  After that, Python.getInstance()
 * is available on any thread.
 *
 * execute() is a regular suspend fun — it runs the Python call on
 * Dispatchers.Default to keep the main thread free, then returns a ToolResult.
 *
 * Result types:
 *   "text"  → ToolResult.Text  (plain string)
 *   "image" → ToolResult.Image (base64-decoded PNG bytes)
 *   "html"  → ToolResult.Text  (full HTML string; UI renders it in a WebView bubble)
 *   "error" → ToolResult.Text  (error JSON)
 */
object PythonRunner {

    suspend fun executeImageEdit(imageB64: String, code: String): ToolResult =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            runCatching {
                val py     = Python.getInstance()
                val runner = py.getModule("runner")
                val result = runner.callAttr("edit_image", imageB64, code)

                val parts = result.asList()
                val type  = parts[0].toString()
                val value = parts[1].toString()

                Log.d(TAG, "edit_image → type=$type value=${value.take(80)}")

                when (type) {
                    "image" -> {
                        val bytes = Base64.decode(value, Base64.DEFAULT)
                        ToolResult.Image(bytes, "Edited image (${bytes.size / 1024} KB PNG)")
                    }
                    "error" -> ToolResult.Text("""{"error":"${
                        value.replace("\\", "\\\\").replace("\"", "\\\"")
                             .replace("\n", "\\n").replace("\r", "\\r")
                    }"}""")
                    else    -> ToolResult.Text(value)
                }
            }.getOrElse { e ->
                Log.e(TAG, "executeImageEdit error", e)
                ToolResult.Text("""{"error":"${e.message?.replace("\"", "'")}"}""")
            }
        }

    suspend fun execute(code: String): ToolResult =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            runCatching {
                val py     = Python.getInstance()
                val runner = py.getModule("runner")
                val result = runner.callAttr("run_code", code)

                // result is a Python list: [type_str, value_str]
                val parts = result.asList()
                val type  = parts[0].toString()
                val value = parts[1].toString()

                Log.d(TAG, "run_code → type=$type value=${value.take(120)}")

                when (type) {
                    "image" -> {
                        val bytes = Base64.decode(value, Base64.DEFAULT)
                        ToolResult.Image(bytes, "Python-generated plot (${bytes.size / 1024} KB PNG)")
                    }
                    "html"  -> ToolResult.Text(value)
                    "error" -> ToolResult.Text("""{"error":"${
                        value.replace("\\", "\\\\").replace("\"", "\\\"")
                             .replace("\n", "\\n").replace("\r", "\\r")
                    }"}""")
                    else    -> ToolResult.Text(value)
                }
            }.getOrElse { e ->
                Log.e(TAG, "PythonRunner error", e)
                ToolResult.Text("""{"error":"${e.message?.replace("\"", "'")}"}""")
            }
        }
}
