import Foundation

/// Registers the `run_python` agentic tool, which executes Python code
/// on-device using the embedded BeeWare CPython runtime.
///
/// Call `PythonTools.register()` once from `AIiOSApp.registerTools()`.
enum PythonTools {

    static func register() {
        ToolRegistry.shared.register(ToolDefinition(
            name: "run_python",
            description: """
                Executes Python code on-device and returns the output. \
                Available libraries: numpy, pandas, matplotlib, plotly, \
                astral, folium, requests, Pillow (PIL), sympy. \
                matplotlib figures are returned as PNG images. \
                plotly figures are returned as interactive HTML. \
                All other output must be assigned to a variable named `result` or use print(). \
                To edit an attached image use the edit_image tool instead.
                """,
            parametersDoc: "code: string — the Python source code to execute",
            argsExample: #"{"code":"import numpy as np\nresult = float(np.sqrt(2))"}"#,
            execute: { args in
                guard let code = args["code"] as? String, !code.isEmpty else {
                    return .text(#"{"error":"'code' parameter is required"}"#)
                }
                return await PythonRunner.execute(code: code)
            }
        ))
    }
}
