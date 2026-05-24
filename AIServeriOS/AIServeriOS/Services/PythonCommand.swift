import Foundation

/// Helpers for the `list tools` and `use tool <request>` chat commands.
/// Mirrors the Flutter `PythonCommand` class — library metadata, prompt
/// construction, and code extraction in one place.
///
/// NOTE: Without an on-device Python runtime (Pyodide), generated code is
/// displayed as a code block rather than executed. Execution can be added
/// later by embedding a WKWebView with a Pyodide bundle.
enum PythonCommand {

    // MARK: - Library registry

    private struct LibInfo {
        let aliases:     [String]
        let description: String
    }

    private static let libs: [(name: String, info: LibInfo)] = [
        ("numpy",      LibInfo(aliases: ["numpy", "np"],          description: "Numerical arrays & math")),
        ("scipy",      LibInfo(aliases: ["scipy", "sp"],          description: "Scientific computing & signal processing")),
        ("pandas",     LibInfo(aliases: ["pandas", "pd"],         description: "Data analysis & DataFrames")),
        ("matplotlib", LibInfo(aliases: ["matplotlib", "plt"],    description: "2D static charts & plots")),
        ("plotly",     LibInfo(aliases: ["plotly", "px", "go"],   description: "Interactive charts")),
        ("astral",     LibInfo(aliases: ["astral"],               description: "Sunrise, sunset, moon phase & solar calculations")),
        ("folium",     LibInfo(aliases: ["folium"],               description: "Interactive Leaflet.js maps with markers, polygons & heatmaps")),
        ("shapely",    LibInfo(aliases: ["shapely"],              description: "Geometric operations — areas, distances & spatial intersections")),
    ]

    // MARK: - Public API

    /// Formatted list of supported libraries for display in the chat.
    static func listMessage() -> String {
        var buf = "Available Python libraries:\n\n"
        for (name, info) in libs {
            let otherAliases = info.aliases.filter { $0 != name }.joined(separator: ", ")
            let aliasSuffix  = otherAliases.isEmpty ? "" : " (aliases: \(otherAliases))"
            buf += "• \(name)\(aliasSuffix) — \(info.description)\n"
        }
        buf += "\nUsage: use tool <request>\n"
        buf += "Example: use tool plot a sine wave\n"
        buf += "The model will choose the best library automatically.\n"
        buf += "\nType \"list tools\" to show this list again."
        return buf
    }

    /// Builds the LLM prompt for a `use tool <request>` command.
    /// Mirrors Flutter's PythonCommand.buildToolPrompt() exactly.
    static func buildToolPrompt(request: String, locationPreamble: String? = nil) -> String {
        let libNames = libs.map(\.name).joined(separator: ", ")
        let locSection = locationPreamble.map { preamble in
            """

PRE-DEFINED VARIABLES (already set before your code runs — do NOT redefine them):
- user_latitude         (float)             — device GPS latitude
- user_longitude        (float)             — device GPS longitude
- user_timezone_offset  (float)             — device UTC offset in hours (e.g. -5.0 for CDT)
- user_timezone         (datetime.timezone) — ready-made tzinfo object; use directly as tzinfo= in astral/datetime calls
Use these directly whenever the task involves the user's current location or local time.
Do NOT hardcode placeholder coordinates or timezones. Do NOT use zoneinfo — use user_timezone instead.

"""
        } ?? ""

        return """
You are a Python code generator. Write code to accomplish the task below.

INSTALLED LIBRARIES (the ONLY third-party imports allowed): \(libNames)

Python standard library modules (math, datetime, json, re, statistics, etc.) are also available.
\(locSection)
Task: \(request)

STRICT RULES — violating any rule will cause a runtime error:
1. Every import must come from the INSTALLED LIBRARIES list or the Python standard library. Do NOT invent or guess library names.
2. Always write every import statement explicitly at the top.
3. For simple maths use the built-in math module — do not import numpy just for basic arithmetic.
4. If the task needs a library NOT on the installed list, solve it with the standard library instead.
5. All output: assign the final answer to a variable named result (e.g. result = 42). CRITICAL EXCEPTIONS:
   - matplotlib: do NOT assign result — the PNG is auto-captured from the open figure. Never write result = "done" or any other string.
   - plotly: do NOT assign result — the figure is auto-captured from the 'fig' variable. If you must assign result manually, use fig.to_html(include_plotlyjs='cdn', full_html=True).
6. Do NOT call exit() or quit() — these raise SystemExit.
   Do NOT use try/except blocks — they hide errors. Write straightforward code without exception handling.
7. Library choice for charts: use plotly for interactive charts; use matplotlib for static plots/images.
8. Do NOT make any network/HTTP requests from Python code.
9. Do NOT call fig.write_image() — kaleido is not available.
10. Do NOT read or write local file paths — use in-memory objects (BytesIO, StringIO) if needed.
11. datetime usage: always use 'import datetime' then 'datetime.date.today()'. Do NOT do 'from datetime import datetime' then call 'datetime.datetime.today()'.

CORRECT IMPORT PATTERNS — use exactly these, no variations:
- numpy:      import numpy as np
- scipy:      from scipy import stats  /  from scipy.optimize import minimize
- pandas:     import pandas as pd
- matplotlib: import matplotlib.pyplot as plt  — do NOT call plt.show() (auto-captured)
- plotly:     import plotly.express as px  OR  import plotly.graph_objects as go  — assign figure to 'fig', do NOT call fig.show()
- astral:     from astral import LocationInfo; from astral.sun import sun; from astral.moon import phase
  LocationInfo: LocationInfo(name="Place", region="", timezone="UTC", latitude=user_latitude, longitude=user_longitude)
  sun() usage: s = sun(location.observer, date=some_date, tzinfo=user_timezone)  — access as s['sunrise'], s['sunset'], s['noon']
  phase() usage: phase(date) returns a float 0–28
- folium:     import folium  — create map as m = folium.Map(location=[lat,lon], zoom_start=n)  — assign result = m.get_root().render()
- shapely:    from shapely.geometry import Point, Polygon, LineString

Return ONLY the Python code block, no explanation.
"""
    }

    // MARK: - Code extraction

    /// Extracts Python source from an LLM response.
    /// Tries ```python fences, then generic fences, then raw text.
    static func extractCode(from response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. ```python ... ```
        if let range = trimmed.range(of: "```python", options: .caseInsensitive),
           let closeRange = trimmed.range(of: "```", range: range.upperBound..<trimmed.endIndex) {
            let code = String(trimmed[range.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { return code }
        }

        // 2. ``` ... ```
        if let open  = trimmed.range(of: "```"),
           let close = trimmed.range(of: "```", range: open.upperBound..<trimmed.endIndex) {
            // skip any language tag on the opening line
            var content = String(trimmed[open.upperBound..<close.lowerBound])
            if let nl = content.firstIndex(of: "\n") {
                content = String(content[content.index(after: nl)...])
            }
            let code = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { return code }
        }

        // 3. Raw fallback
        return trimmed
    }
}
