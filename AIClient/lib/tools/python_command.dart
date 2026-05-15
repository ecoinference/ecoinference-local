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
    'skyfield': (aliases: ['skyfield'], description: 'Astronomy — precise moon phase, planet positions & rise/set times'),
    'folium': (aliases: ['folium'], description: 'Interactive Leaflet.js maps with markers, polygons & heatmaps'),
    'shapely': (aliases: ['shapely'], description: 'Geometric operations — areas, distances & spatial intersections'),
    'geopy': (aliases: ['geopy'], description: 'Distance calculations between coordinates & geocoding'),
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns the canonical library name for [input], or `null` if unrecognised.
  /// Matching is case-insensitive.
  static String? resolveLibrary(String input) {
    final lower = input.toLowerCase().trim();
    for (final entry in _libs.entries) {
      if (entry.value.aliases.contains(lower)) return entry.key;
    }
    return null;
  }

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
      '\nUsage: use python <lib> <request>\n'
      'Example: use python plt plot a sine wave',
    );
    return buf.toString().trimRight();
  }

  /// Builds the prompt sent to the LLM when the user runs `use python <lib> <request>`.
  static String buildCodePrompt(String library, String request) {
    final extra = switch (library) {
      'plotly' =>
        'For Plotly: create a fig variable (it will be auto-captured). '
        'Do NOT call fig.show().',
      'matplotlib' =>
        'For matplotlib: create the plot (it will be auto-captured). '
        'Do NOT call plt.show().',
      'folium' =>
        'For folium: create a map variable (e.g. m = folium.Map(...)). '
        'At the end assign: result = m._repr_html_() '
        'This returns the map as an HTML string for display.',
      'astral' =>
        'Use the astral and astral.sun modules. '
        'Assign a formatted text summary to result (e.g. result = f"Sunrise: {sunrise}").',
      'skyfield' =>
        'Use the skyfield.api module. '
        'Assign a formatted text summary to result.',
      _ =>
        'For text or numeric results: assign the final value to a variable '
        'named result (e.g. result = 42).',
    };

    return 'Generate Python code using $library to do the following:\n\n'
        '$request\n\n'
        '$extra\n\n'
        'Return ONLY the Python code block, no explanation.';
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
