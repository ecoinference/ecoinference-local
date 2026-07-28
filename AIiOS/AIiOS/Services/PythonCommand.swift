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
    ///
    /// Kept deliberately compact — this instructional text and the model's
    /// response share one fixed total token budget (see
    /// `ModelInfo.maxContextTokens`), so every character spent here is a
    /// character the generated code doesn't get. Confirmed truncating
    /// mid-statement on-device with the original, more verbose version
    /// (2026-07-28). Also explicitly asks for compact, non-human-readable
    /// code (short names, no comments/blank lines) — Python runs identically
    /// either way, so this trims the response's own token cost for free.
    static func buildToolPrompt(request: String, locationPreamble: String? = nil) -> String {
        let libNames = libs.map(\.name).joined(separator: ",")
        let locSection = locationPreamble.map { _ in
            " Pre-defined(don't redefine):user_latitude,user_longitude(floats),user_timezone_offset(float,UTC hrs),user_timezone(tzinfo)—use for location/time tasks,never hardcode,never zoneinfo."
        } ?? ""

        return """
Python code generator. Task:\(request)
Write MINIMAL code:short names,no comments/blank lines/docstrings,semicolons where natural. Correct>readable.
Only import:\(libNames),or stdlib. Never guess a library.\(locSection)
Rules:scalar-only math→use math not numpy(numpy is for arrays—always use numpy for array/vectorized math). result=<answer> EXCEPT matplotlib(never set result,PNG auto-captured) and plotly(never set result,fig auto-captured;else fig.to_html(include_plotlyjs='cdn',full_html=True)). No exit/quit,no try/except,no network,no file I/O(use BytesIO/StringIO),no fig.write_image(). plotly=interactive,matplotlib=static. datetime:import datetime;datetime.date.today() not from datetime import datetime.
Imports:numpy as np|from scipy import stats/from scipy.optimize import minimize|pandas as pd|matplotlib.pyplot as plt(no plt.show())|plotly.express as px/plotly.graph_objects as go(assign fig,no fig.show())|astral:from astral import LocationInfo;from astral.sun import sun;from astral.moon import phase—LocationInfo(name="P",region="",timezone="UTC",latitude=user_latitude,longitude=user_longitude);sun(location.observer,date=d,tzinfo=user_timezone)→s['sunrise']/s['sunset']/s['noon'];phase(date)→float 0-28|folium:import folium;m=folium.Map(location=[lat,lon],zoom_start=n);result=m.get_root().render()|shapely:from shapely.geometry import Point,Polygon,LineString
Return ONLY code,no explanation,no fence.
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

        // 3. No matched fence pair. Two real cases seen in practice:
        // (a) the response was cut off before the model wrote a closing ```
        //     (leading marker present, no trailing one), or
        // (b) the model started straight into code with no opening fence at
        //     all, but still tacked on a trailing ``` out of habit (trailing
        //     marker present, no leading one).
        // Either way, leaving an unmatched fence marker embedded in the
        // "code" guarantees a Python syntax error, so strip whichever single
        // marker is actually present at the start and/or end — independently,
        // since only one of the two may be there.
        var text = trimmed
        if let range = text.range(of: "```python", options: [.caseInsensitive, .anchored]) {
            text = String(text[range.upperBound...])
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
            if let nl = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: nl)...])
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("```") {
            text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.isEmpty ? nil : text
    }
}
