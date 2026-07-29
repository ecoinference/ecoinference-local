import UIKit

/// The result of a tool execution. Mirrors Android's ToolResult sealed class.
///
///  - text:  A JSON / plain-text string the model reads in <tool_result>.
///  - image: A rendered UIImage (chart, etc.) + caption the model reads.
///           The UIImage is forwarded to the chat UI for inline display.
enum ToolResult {
    case text(String)
    case image(UIImage, caption: String)

    /// What the model receives in the <tool_result> block.
    var modelText: String {
        switch self {
        case .text(let s):           return s
        case .image(_, let caption): return caption
        }
    }

    /// What the human-facing tool chat bubble shows. Tool error results are
    /// `{"error":"..."}` JSON meant for the model to read and self-correct
    /// from — showing that raw envelope to the user reads as leaked internal
    /// state, not a real error message. This unwraps it into a short,
    /// human-readable line; anything that isn't that exact shape (plain-text
    /// fallback messages, successful results) passes through unchanged.
    var displayText: String { Self.humanReadable(modelText) }

    static func humanReadable(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj.count == 1,
              let message = obj["error"] as? String
        else { return raw }

        // A Python traceback's last non-empty line is the actual exception
        // summary (e.g. "ValueError: x must be positive") — show just that,
        // not the full multi-frame trace.
        let lines = message.split(separator: "\n", omittingEmptySubsequences: true)
        let summary = lines.last.map(String.init) ?? message
        return "⚠️ \(summary)"
    }
}
