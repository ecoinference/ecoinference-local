/// Sealed result type returned by every agentic tool.
///
/// [TextToolResult]  — plain text, fed directly back to the LLM.
/// [ImageToolResult] — base64 PNG (e.g. matplotlib); shown as image bubble.
/// [HtmlToolResult]  — self-contained HTML (e.g. Plotly); opened full-screen.
sealed class ToolResult {
  const ToolResult();
}

class TextToolResult extends ToolResult {
  const TextToolResult(this.text);
  final String text;
}

class ImageToolResult extends ToolResult {
  const ImageToolResult({required this.base64DataUrl, this.caption = 'Chart generated.'});
  /// "data:image/png;base64,..."
  final String base64DataUrl;
  /// Short description sent to the LLM in place of the raw base64.
  final String caption;
}

class HtmlToolResult extends ToolResult {
  const HtmlToolResult({required this.html, this.caption = 'Interactive chart generated.'});
  /// Full self-contained HTML page (Plotly include_plotlyjs='cdn').
  final String html;
  /// Short description sent to the LLM.
  final String caption;
}
