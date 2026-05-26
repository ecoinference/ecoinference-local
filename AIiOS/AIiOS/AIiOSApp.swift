import SwiftUI
import Foundation

@main
struct EcoInferenceApp: App {

    @StateObject private var appState = AppState.shared

    init() {
        redirectNativeStderrToLog()
        SettingsService.shared.load()
        registerTools()
    }

    /// Redirect process stderr → Documents/native_stderr.log so that LiteRT-LM's
    /// C++ error messages (which go to stderr, not os_log) are capturable from the Mac.
    private func redirectNativeStderrToLog() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logURL = docs.appendingPathComponent("native_stderr.log")
        // Truncate on each launch so it stays small
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        freopen(logURL.path, "w", stderr)
        // freopen switches stderr to fully-buffered mode (because it's now a file,
        // not a tty). Partial buffers are only flushed when full, so the tail of
        // the native C++ log is lost when the process returns from engine_create.
        // Switch to line-buffered so every '\n' causes an immediate disk flush.
        setvbuf(stderr, nil, _IOLBF, 0)
    }

    // MARK: - Agentic tool registration

    private func registerTools() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "get_location",
            description:   "Returns the device's current GPS coordinates and timezone.",
            parametersDoc: "(no parameters)",
            argsExample:   "{}",
            execute: { _ in
                do {
                    let loc = try await LocationService.shared.requestLocation()
                    return loc.toolResult
                } catch {
                    return "Location unavailable: \(error.localizedDescription)"
                }
            }
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    // MARK: - URL scheme handler
    //
    // Supported URLs:
    //   ecoinference://chat
    //   ecoinference://chat?message=<text>&send=1&system=<text>
    //   ecoinference://models
    //   ecoinference://models/load?id=<model_id>
    //   ecoinference://settings
    //   ecoinference://x-callback-url/infer?prompt=<text>&x-success=<url>

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "ecoinference" else { return }

        let host   = url.host?.lowercased() ?? ""
        let path   = url.path.lowercased()
        let comps  = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query  = { (key: String) -> String? in
            comps?.queryItems?.first(where: { $0.name == key })?.value
        }

        switch host {

        case "chat":
            let prefill    = query("message")
            let autoSend   = query("send") == "1"
            let system     = query("system")
            appState.deepLink = .openChat(
                prefill:      prefill,
                autoSend:     autoSend,
                systemPrompt: system
            )

        case "models":
            if path.hasPrefix("/load"), let id = query("id") {
                appState.deepLink = .loadModel(id: id)
            } else {
                appState.deepLink = .openModels
            }

        case "settings":
            appState.deepLink = .openSettings

        case "x-callback-url":
            // ecoinference://x-callback-url/infer?prompt=<text>&x-success=<url>
            if path.hasPrefix("/infer"), let prompt = query("prompt") {
                let callbackURL = query("x-success").flatMap { URL(string: $0) }
                appState.deepLink = .backgroundInfer(
                    prompt:      prompt,
                    callbackURL: callbackURL
                )
            }

        default:
            break
        }
    }
}
