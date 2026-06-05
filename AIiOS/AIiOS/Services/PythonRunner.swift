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
        // Use .background priority so iOS's cpu_resource watchdog applies its
        // more lenient limit (background tasks get more CPU slack than foreground
        // userInitiated tasks).  Heavy Python package imports (numpy, matplotlib)
        // can saturate the CPU for 30-60 s on first run; .userInitiated caused
        // the 90%-for-100s watchdog kill at the 50%-over-180s limit.
        await Task.detached(priority: .background) {
            runSync(code: code)
        }.value
    }

    // MARK: - Synchronous runner (must not be called on main thread)

    private static func runSync(code: String) -> ToolResult {
        // Acquire the GIL before any PythonKit / CPython C-API call.
        // PythonGIL.enableMultiThreading() was called in EmbeddedPython.start(),
        // releasing the GIL from the main thread.  Every background thread
        // must re-acquire it here or we get SIGSEGV (signal 11).
        let gilState = PythonGIL.ensure()
        defer { PythonGIL.release(gilState) }

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
