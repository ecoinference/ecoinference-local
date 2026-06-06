package ai.ecoinference.app.tools

/**
 * Registers the run_python tool.
 *
 * Executes arbitrary Python 3.11 code on-device via Chaquopy (native CPython).
 * No CDN, no WebView, no network required — packages are bundled in the APK.
 *
 * Supported libraries: numpy, pandas, scipy, matplotlib, plotly, astral,
 *                      folium, shapely.
 *
 * Results:
 *   - Plain text  — print() output or result= assignment
 *   - PNG image   — matplotlib figures (auto-captured)
 *   - HTML        — plotly / folium interactive charts
 */
object PythonTools {

    fun register() {
        ToolRegistry.register(ToolDefinition(
            name          = "run_python",
            description   = "Executes Python 3 code on-device (native CPython via Chaquopy). " +
                            "Use for maths, data analysis, plotting, or symbolic computation. " +
                            "Available libraries: numpy, pandas, scipy, matplotlib, plotly, " +
                            "astral, folium, shapely, PIL (Pillow), sympy. " +
                            "Assign output to 'result' or use print() — figures are captured automatically. " +
                            "Sympy example: from sympy import symbols, solve; x = symbols('x'); result = str(solve(x**2 - 4, x)). " +
                            "For editing a user-attached image, use the edit_image tool instead.",
            parametersDoc = "code: string — Python code to execute",
            argsExample   = """{"code":"import numpy as np\nresult = float(np.sqrt(144))"}""",
            execute       = { args ->
                val code = extractCode(args)
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'code' parameter missing"}""")
                PythonRunner.execute(code)
            }
        ))
    }

    private fun extractCode(args: String): String? {
        val match = Regex(""""code"\s*:\s*"((?:[^"\\]|\\.)*)"""", RegexOption.DOT_MATCHES_ALL)
            .find(args) ?: return null
        return match.groupValues[1]
            .replace("\\n", "\n")
            .replace("\\t", "\t")
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    }
}
