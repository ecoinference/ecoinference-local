import Foundation
import UIKit
import PythonKit

/// Executes Python code on-device using the embedded BeeWare CPython runtime.
///
/// Mirrors Android's PythonRunner.kt. Call `PythonRunner.execute(code:)` from
/// any async context; it dispatches to a background thread to keep the main
/// runloop free.
enum PythonRunner {

    // MARK: - Execute

    /// Executes `code` and returns a `ToolResult`.
    ///
    /// - Returns: `.image` for matplotlib PNG output, `.text` for HTML/text/error.
    static func execute(code: String) async -> ToolResult {
        await Task.detached(priority: .userInitiated) {
            runSync(code: code)
        }.value
    }

    // MARK: - Synchronous runner (must not be called on main thread)

    private static func runSync(code: String) -> ToolResult {
        do {
            let runner = try Python.attemptImport("runner")
            let result = runner.run_code(code)
            let parts  = Array(result)
            guard parts.count == 2 else {
                return .text(#"{"error":"runner returned unexpected result"}"#)
            }
            let type  = String(parts[0]) ?? "error"
            let value = String(parts[1]) ?? ""

            switch type {
            case "image":
                guard let data  = Data(base64Encoded: value),
                      let image = UIImage(data: data) else {
                    return .text(#"{"error":"failed to decode PNG from runner"}"#)
                }
                let kb = data.count / 1024
                return .image(image, caption: "Python-generated plot (\(kb) KB PNG)")

            case "html":
                return .text(value)

            case "error":
                let escaped = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                return .text(#"{"error":"\#(escaped)"}"#)

            default:           // "text"
                return .text(value)
            }

        } catch {
            let msg = error.localizedDescription
                .replacingOccurrences(of: "\"", with: "'")
            return .text(#"{"error":"\#(msg)"}"#)
        }
    }
}
