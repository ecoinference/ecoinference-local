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
}
