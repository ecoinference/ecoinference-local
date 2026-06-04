package ai.ecoinference.app.tools

import android.content.Context

/**
 * Registers the run_python tool.
 *
 * run_python executes arbitrary Python 3 code in an on-device Pyodide
 * (WebAssembly) runtime.  Supported libraries: numpy, pandas, scipy,
 * matplotlib, plotly, astral, folium, shapely.
 *
 * Results are returned as:
 *   - Plain text  — print() output, expression values, or result= assignment
 *   - PNG image   — matplotlib figures (auto-captured)
 *   - HTML        — plotly / folium interactive charts
 */
object PythonTools {

    fun register(context: Context) {
        PythonRunner.initialize(context)

        ToolRegistry.register(ToolDefinition(
            name        = "run_python",
            description = "Executes Python 3 code on-device via Pyodide (WebAssembly). " +
                          "Use for maths, data analysis, plotting, or any computation. " +
                          "Supported libraries: numpy, pandas, scipy, matplotlib, plotly, " +
                          "astral, folium, shapely. " +
                          "Assign output to 'result' or use print() — figures are captured automatically.",
            parametersDoc = "code: string — the Python code to execute",
            argsExample   = """{"code":"import numpy as np\nresult = float(np.sqrt(144))"}""",
            execute       = { args ->
                val code = extractCode(args)
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'code' parameter missing"}""")
                PythonRunner.execute(code)
            }
        ))
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Extract the "code" string from a JSON args blob.
     * Handles both compact and pretty-printed JSON, and escaped newlines.
     */
    private fun extractCode(args: String): String? {
        // Try simple regex first (handles most model outputs)
        val match = Regex(""""code"\s*:\s*"((?:[^"\\]|\\.)*)"""", RegexOption.DOT_MATCHES_ALL)
            .find(args) ?: return null
        return match.groupValues[1]
            .replace("\\n", "\n")
            .replace("\\t", "\t")
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    }
}
