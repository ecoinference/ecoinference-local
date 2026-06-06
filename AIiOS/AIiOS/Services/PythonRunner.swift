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

    // MARK: - Image edit

    /// Executes Pillow image-editing code on a background thread.
    /// `imageB64` is a base64-encoded JPEG/PNG string.
    /// The code receives `img` (PIL Image) and must set `result_img`.
    static func executeImageEdit(imageB64: String, code: String) async -> ToolResult {
        await Task.detached(priority: .background) {
            runImageEditSync(imageB64: imageB64, code: code)
        }.value
    }

    private static func runImageEditSync(imageB64: String, code: String) -> ToolResult {
        let gilState = PythonGIL.ensure()
        defer { PythonGIL.release(gilState) }

        do {
            let runner = try Python.attemptImport("runner")
            let result = runner.edit_image(imageB64, code)
            let parts  = Array(result)
            guard parts.count == 2 else {
                return .text(#"{"error":"runner.edit_image returned unexpected result"}"#)
            }
            let type  = String(parts[0]) ?? "error"
            let value = String(parts[1]) ?? ""

            switch type {
            case "image":
                guard let data  = Data(base64Encoded: value),
                      let image = UIImage(data: data) else {
                    return .text(#"{"error":"failed to decode edited image PNG"}"#)
                }
                return .image(image, caption: "Edited image")
            case "error":
                let escaped = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                return .text(#"{"error":"\#(escaped)"}"#)
            default:
                return .text(value)
            }
        } catch {
            let msg = error.localizedDescription
                .replacingOccurrences(of: "\"", with: "'")
            return .text(#"{"error":"\#(msg)"}"#)
        }
    }

    // MARK: - QR code generation

    /// Generates a QR code PNG using the `qrcode` Python library.
    /// Returns `.image` on success or `.text` with an error JSON on failure.
    static func executeGenerateQr(text: String, boxSize: Int, border: Int) async -> ToolResult {
        await Task.detached(priority: .background) {
            runGenerateQrSync(text: text, boxSize: boxSize, border: border)
        }.value
    }

    private static func runGenerateQrSync(text: String, boxSize: Int, border: Int) -> ToolResult {
        let gilState = PythonGIL.ensure()
        defer { PythonGIL.release(gilState) }

        do {
            let runner = try Python.attemptImport("runner")
            let result = runner.generate_qr(text, boxSize, border)
            let parts  = Array(result)
            guard parts.count == 2 else {
                return .text(#"{"error":"runner.generate_qr returned unexpected result"}"#)
            }
            let type  = String(parts[0]) ?? "error"
            let value = String(parts[1]) ?? ""

            switch type {
            case "image":
                guard let data  = Data(base64Encoded: value),
                      let image = UIImage(data: data) else {
                    return .text(#"{"error":"failed to decode QR code PNG"}"#)
                }
                return .image(image, caption: "QR code for: \(text.prefix(60))")
            case "error":
                let escaped = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                return .text(#"{"error":"\#(escaped)"}"#)
            default:
                return .text(value)
            }
        } catch {
            let msg = error.localizedDescription
                .replacingOccurrences(of: "\"", with: "'")
            return .text(#"{"error":"\#(msg)"}"#)
        }
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
