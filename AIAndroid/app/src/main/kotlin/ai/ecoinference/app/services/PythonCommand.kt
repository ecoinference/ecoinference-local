package ai.ecoinference.app.services

/**
 * Helpers for the `list tools` and `use tool <request>` chat commands.
 * Mirrors iOS's PythonCommand.swift — library metadata, prompt construction,
 * and code extraction in one place. Ported 2026-07-28; iOS had no Android
 * equivalent of this command at all until then.
 */
object PythonCommand {

    // ── Library registry ─────────────────────────────────────────────────────

    private data class LibInfo(val aliases: List<String>, val description: String)

    private val libs: List<Pair<String, LibInfo>> = listOf(
        "numpy"      to LibInfo(listOf("numpy", "np"),        "Numerical arrays & math"),
        "scipy"      to LibInfo(listOf("scipy", "sp"),        "Scientific computing & signal processing"),
        "pandas"     to LibInfo(listOf("pandas", "pd"),       "Data analysis & DataFrames"),
        "matplotlib" to LibInfo(listOf("matplotlib", "plt"),  "2D static charts & plots"),
        "plotly"     to LibInfo(listOf("plotly", "px", "go"), "Interactive charts"),
        "astral"     to LibInfo(listOf("astral"),             "Sunrise, sunset, moon phase & solar calculations"),
        "folium"     to LibInfo(listOf("folium"),             "Interactive Leaflet.js maps with markers, polygons & heatmaps"),
        "shapely"    to LibInfo(listOf("shapely"),            "Geometric operations — areas, distances & spatial intersections"),
    )

    // ── Public API ────────────────────────────────────────────────────────────

    /** Formatted list of supported libraries for display in the chat. */
    fun listMessage(): String {
        val buf = StringBuilder("Available Python libraries:\n\n")
        for ((name, info) in libs) {
            val otherAliases = info.aliases.filter { it != name }.joinToString(", ")
            val aliasSuffix  = if (otherAliases.isEmpty()) "" else " (aliases: $otherAliases)"
            buf.append("• $name$aliasSuffix — ${info.description}\n")
        }
        buf.append("\nUsage: use tool <request>\n")
        buf.append("Example: use tool plot a sine wave\n")
        buf.append("The model will choose the best library automatically.\n")
        buf.append("\nType \"list tools\" to show this list again.")
        return buf.toString()
    }

    /**
     * Builds the LLM prompt for a `use tool <request>` command.
     *
     * Kept deliberately compact — this instructional text and the model's
     * response share one fixed total token budget (model's maxContextTokens),
     * so every character spent here is a character the generated code
     * doesn't get. Also explicitly asks for compact, non-human-readable code
     * (short names, no comments/blank lines) — Python runs identically
     * either way, so this trims the response's own token cost for free.
     * Mirrors iOS's PythonCommand.buildToolPrompt() text exactly.
     */
    fun buildToolPrompt(request: String, locationPreamble: String? = null): String {
        val libNames = libs.joinToString(",") { it.first }
        val locSection = if (locationPreamble != null)
            " Pre-defined(don't redefine):user_latitude,user_longitude(floats),user_timezone_offset(float,UTC hrs),user_timezone(tzinfo)—use for location/time tasks,never hardcode,never zoneinfo."
        else ""

        return """
Python code generator. Task:$request
Write MINIMAL code:short names,no comments/blank lines/docstrings,semicolons where natural. Correct>readable. Prefer one-liners/indexing over if-chains; if you DO write if/for/def, indent the body 4 spaces on its own line—never leave it flush left.
Only import:$libNames,or stdlib. Never guess a library.$locSection
Rules:scalar-only math→use math not numpy(numpy is for arrays—always use numpy for array/vectorized math). result=<answer> EXCEPT matplotlib(never set result,PNG auto-captured) and plotly(never set result,fig auto-captured;else fig.to_html(include_plotlyjs='cdn',full_html=True)). No exit/quit,no try/except,no network,no file I/O(use BytesIO/StringIO),no fig.write_image(). plotly=interactive,matplotlib=static. datetime:import datetime;datetime.date.today() not from datetime import datetime.
Imports:numpy as np|from scipy import stats/from scipy.optimize import minimize|pandas as pd|matplotlib.pyplot as plt(no plt.show())|plotly.express as px/plotly.graph_objects as go(assign fig,no fig.show())|astral:from astral import LocationInfo;from astral.sun import sun;from astral.moon import phase—LocationInfo(name="P",region="",timezone="UTC",latitude=user_latitude,longitude=user_longitude);sun(location.observer,date=d,tzinfo=user_timezone)→s['sunrise']/s['sunset']/s['noon'];phase(d)→float 0-27.99,date arg ONLY(no location),a NUMBER not an object;name it EXACTLY:import bisect;result=["New Moon","Waxing Crescent","First Quarter","Waxing Gibbous","Full Moon","Waning Gibbous","Last Quarter","Waning Crescent","New Moon"][bisect.bisect([1.75,5.25,8.75,12.25,15.75,19.25,22.75,26.25],phase(d))]|folium:import folium;m=folium.Map(location=[lat,lon],zoom_start=n);result=m.get_root().render()|shapely:from shapely.geometry import Point,Polygon,LineString
Return ONLY code,no explanation,no fence.
""".trimIndent()
    }

    // ── Code extraction ──────────────────────────────────────────────────────

    /**
     * Extracts Python source from an LLM response. Tries ```python fences,
     * then generic fences, then strips an unmatched single marker at either
     * end, then falls back to the raw trimmed text.
     */
    fun extractCode(response: String): String? {
        val trimmed = response.trim()
        if (trimmed.isEmpty()) return null

        // 1. ```python ... ```
        val pyFenceIdx = trimmed.indexOf("```python", ignoreCase = true)
        if (pyFenceIdx >= 0) {
            val openEnd = pyFenceIdx + "```python".length
            val closeIdx = trimmed.indexOf("```", openEnd)
            if (closeIdx >= 0) {
                val code = trimmed.substring(openEnd, closeIdx).trim()
                if (code.isNotEmpty()) return code
            }
        }

        // 2. ``` ... ```
        val openIdx = trimmed.indexOf("```")
        if (openIdx >= 0) {
            val closeIdx = trimmed.indexOf("```", openIdx + 3)
            if (closeIdx >= 0) {
                var content = trimmed.substring(openIdx + 3, closeIdx)
                val nl = content.indexOf('\n')
                if (nl >= 0) content = content.substring(nl + 1)
                val code = content.trim()
                if (code.isNotEmpty()) return code
            }
        }

        // 3. No matched fence pair. Two real cases seen in practice on iOS
        // (confirmed live, 2026-07-28), equally possible here:
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
        val anchoredPy = text.indexOf("```python", ignoreCase = true)
        if (anchoredPy == 0) {
            text = text.substring("```python".length)
        } else if (text.startsWith("```")) {
            text = text.substring(3)
            val nl = text.indexOf('\n')
            if (nl >= 0) text = text.substring(nl + 1)
        }
        text = text.trim()
        if (text.endsWith("```")) {
            text = text.substring(0, text.length - 3).trim()
        }

        return text.ifEmpty { null }
    }
}
