import Foundation

/// Registers the `generate_qr` agentic tool.
///
/// Generates a QR code PNG using the `qrcode` Python library (bundled in app_packages).
/// Supports any text payload: URLs, plain text, WiFi credentials, vCard contacts.
///
/// Call `QrCodeTools.register()` once from `AIiOSApp.registerTools()`.
enum QrCodeTools {

    static func register() {
        ToolRegistry.shared.register(ToolDefinition(
            name: "generate_qr",
            description: "Generates a QR code PNG image from any text, URL, WiFi string, or vCard. " +
                         "Returns an inline image. " +
                         "box_size controls pixel size per module (1-20, default 10). " +
                         "border controls quiet-zone width in modules (0-10, default 4).",
            parametersDoc: "text: string (required) — content to encode; " +
                           "box_size: int (optional, default 10); border: int (optional, default 4)",
            argsExample: #"{"text":"https://ecoinference.ai"}"#,
            execute: { args in
                guard let text = args["text"] as? String, !text.isEmpty else {
                    return .text(#"{"error":"'text' parameter is required"}"#)
                }
                let boxSize = (args["box_size"] as? Int) ?? 10
                let border  = (args["border"]   as? Int) ?? 4
                return await PythonRunner.executeGenerateQr(
                    text: text, boxSize: boxSize, border: border)
            }
        ))
    }
}
