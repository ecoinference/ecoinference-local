/// Helper for the `list python` and `use python <lib> <details>` chat commands.
///
/// Keeps all library metadata, prompt construction, and code extraction logic
/// in one place so [ChatScreen] stays focused on UI concerns.
class PythonCommand {
  PythonCommand._();

  // ── Library registry ────────────────────────────────────────────────────────

  /// Maps each canonical library name to its recognised aliases (lower-cased)
  /// and a short human-readable description.
  static const _libs = <String, ({List<String> aliases, String description})>{
    'numpy': (aliases: ['numpy', 'np'], description: 'Numerical arrays & math'),
    'scipy': (
      aliases: ['scipy', 'sp'],
      description: 'Scientific computing & signal processing'
    ),
    'pandas': (aliases: ['pandas', 'pd'], description: 'Data analysis & DataFrames'),
    'matplotlib': (aliases: ['matplotlib', 'plt'], description: '2D static charts & plots'),
    'plotly': (aliases: ['plotly', 'px', 'go'], description: 'Interactive charts'),
    'astral': (aliases: ['astral'], description: 'Sunrise, sunset, moon phase & solar calculations'),
    'folium': (aliases: ['folium'], description: 'Interactive Leaflet.js maps with markers, polygons & heatmaps'),
    'shapely': (aliases: ['shapely'], description: 'Geometric operations — areas, distances & spatial intersections'),
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Formatted list of all supported libraries — suitable for a chat bubble.
  static String listMessage() {
    final buf = StringBuffer('Available Python libraries:\n\n');
    for (final entry in _libs.entries) {
      final canonical = entry.key;
      final aliases = entry.value.aliases
          .where((a) => a != canonical)
          .join(', ');
      final aliasStr = aliases.isNotEmpty ? ' (aliases: $aliases)' : '';
      buf.writeln('• $canonical$aliasStr — ${entry.value.description}');
    }
    buf.write(
      '\nUsage: use tool <request>\n'
      'Example: use tool plot a sine wave\n'
      'The model will choose the best library automatically.\n'
      '\nType "list tools" to show this list again.',
    );
    return buf.toString().trimRight();
  }

  /// Builds the prompt sent to the LLM for a `use tool <request>` command.
  /// Lists every available library so the model only picks supported ones.
  static String buildToolPrompt(String request) {
    final libNames = _libs.keys.join(', ');
    return '''
You are a Python code generator. Write code to accomplish the task below.

INSTALLED LIBRARIES (the ONLY third-party imports allowed): $libNames

Python standard library modules (math, datetime, json, re, statistics, etc.) are also available.

PRE-DEFINED VARIABLES (already set before your code runs — do NOT redefine them):
- user_latitude         (float)            — device GPS latitude
- user_longitude        (float)            — device GPS longitude
- user_timezone_offset  (float)            — device UTC offset in hours (e.g. -5.0 for CDT)
- user_timezone         (datetime.timezone) — ready-made tzinfo object; use directly as tzinfo= in astral/datetime calls
Use these directly whenever the task involves the user's current location or local time. Do NOT hardcode placeholder coordinates or timezones. Do NOT use zoneinfo or look up a timezone from coordinates — use user_timezone instead.

Task: $request

STRICT RULES — violating any rule will cause a runtime error:
1. Every import must come from the INSTALLED LIBRARIES list or the Python standard library. Do NOT invent or guess library names.
2. Always write every import statement explicitly at the top.
3. For simple maths use the built-in math module — do not import numpy just for basic arithmetic.
4. If the task needs a library NOT on the installed list, solve it with the standard library instead.
5. All output: assign the final answer to a variable named result (e.g. result = 42). CRITICAL EXCEPTIONS:
   - matplotlib: do NOT assign result at all — the PNG is auto-captured from the open figure. Never write result = "done", result = "Plot generated", result = "success", or any other string.
   - plotly: do NOT assign result — the figure is auto-captured from the 'fig' variable. If you must assign result manually, you MUST use fig.to_html(include_plotlyjs='cdn', full_html=True) — omitting full_html=True returns a bare <div> fragment, not valid HTML.
6. Do NOT call exit() or quit() anywhere in the code — these raise SystemExit and crash the runner.
   Do NOT use try/except blocks — they hide errors and cause NameError when variables assigned inside try are used outside it. Write straightforward code without exception handling.
7. Library choice for charts: use plotly for interactive charts; use matplotlib for static plots/images. If the request uses the word "interactive" or asks for hoverable/zoomable charts, always use plotly.
8. Do NOT make any network/HTTP requests from Python code — all outbound HTTP is blocked. This means: no pd.read_html(url), no scipy.datasets, no requests/urllib calls.
9. Do NOT call fig.write_image() — kaleido is not available.
10. Do NOT read or write local file paths — there is no real filesystem. Use in-memory objects (BytesIO, StringIO) if intermediate storage is needed.
11. datetime usage: always use 'import datetime' then 'datetime.date.today()' or 'datetime.datetime.now()'. Do NOT do 'from datetime import datetime' then call 'datetime.datetime.today()' — that is a double-reference error.

CORRECT IMPORT PATTERNS — use exactly these, no variations:
- numpy:      import numpy as np
- scipy:      from scipy import stats  /  from scipy.optimize import minimize  /  from scipy.signal import find_peaks  /  from scipy.spatial.distance import cdist
- pandas:     import pandas as pd
- matplotlib: import matplotlib.pyplot as plt  — do NOT call plt.show() (auto-captured)
- plotly:     import plotly.express as px  OR  import plotly.graph_objects as go  — assign figure to 'fig', do NOT call fig.show() (auto-captured)
- astral:     from astral import LocationInfo; from astral.sun import sun; from astral.moon import phase
  LocationInfo: LocationInfo(name="Place", region="", timezone="UTC", latitude=user_latitude, longitude=user_longitude)  — always pass timezone="UTC" when using user_timezone as tzinfo; kwargs are 'latitude'/'longitude', NOT 'lat'/'lon'
  sun() usage: s = sun(location.observer, date=some_date, tzinfo=user_timezone)  — first arg is POSITIONAL (location.observer), never write observer=location.observer or location.observer=anything; s is a DICT; access as s['sunrise'], s['sunset'], s['noon'], s['dawn'], s['dusk']  — do NOT call sun.sunrise() or sun.sunset(), those do not exist; do NOT use zoneinfo or look up timezone from coordinates
  phase() usage: phase(date) returns a float 0–28 (moon age in days)
  assign formatted text to result
- folium:     import folium  — create map as m = folium.Map(location=[lat,lon], zoom_start=n)  — assign result = m.get_root().render() at the end (NOT m._repr_html_() — that returns a div fragment, not a full HTML document)
- shapely:    from shapely.geometry import Point, Polygon, LineString, MultiPolygon  /  from shapely.ops import unary_union
- distance:   use the math module only — haversine formula for GPS distance: import math; def haversine(lat1,lon1,lat2,lon2): R=6371; p1,p2=math.radians(lat1),math.radians(lat2); dp=math.radians(lat2-lat1); dl=math.radians(lon2-lon1); a=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2; return 2*R*math.asin(math.sqrt(a))

Return ONLY the Python code block, no explanation.
'''.trim();
  }

  /// Extracts Python source code from an LLM response.
  ///
  /// Tries, in order:
  /// 1. Content inside ```python … ``` fences.
  /// 2. Content inside ``` … ``` fences (any language tag).
  /// 3. The raw response, trimmed (fallback).
  ///
  /// Returns `null` only when the response is empty.
  static final _pyFenceRe =
      RegExp(r'```python\s*\n([\s\S]*?)```', caseSensitive: false);
  static final _genericFenceRe = RegExp(r'```[^\n]*\n([\s\S]*?)```');

  static String? extractCode(String llmResponse) {
    final trimmed = llmResponse.trim();
    if (trimmed.isEmpty) return null;

    // 1. ```python … ```
    final pyMatch = _pyFenceRe.firstMatch(trimmed);
    if (pyMatch != null) return pyMatch.group(1)!.trim();

    // 2. ``` … ```
    final gMatch = _genericFenceRe.firstMatch(trimmed);
    if (gMatch != null) return gMatch.group(1)!.trim();

    // 3. Raw fallback
    return trimmed;
  }
}
