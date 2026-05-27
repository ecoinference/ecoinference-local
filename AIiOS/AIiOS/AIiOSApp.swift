import SwiftUI
import Foundation

@main
struct EcoInferenceApp: App {

    @StateObject private var appState = AppState.shared

    init() {
        redirectNativeStderrToLog()
        SettingsService.shared.load()
        registerTools()

        // ── Fix black safe-area bars on iOS 26 ───────────────────────────────
        // On iOS 26 the UIHostingController's view and the UIWindow both default
        // to clear/nil backgrounds, so the raw black window surface shows through
        // in the Dynamic Island region (top) and home-indicator region (bottom).
        //
        // UIWindow.appearance() fires before UIKit creates the window — iOS 26
        // then overwrites it during scene setup.  onAppear also races with scene
        // initialisation.
        //
        // UIApplication.didBecomeActiveNotification fires AFTER the scene and all
        // its windows are fully initialised, so our values stick.  It also re-fires
        // on every foreground, self-healing any subsequent system reset.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            EcoInferenceApp.fixWindowBackgrounds()
        }
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
                    return .text(loc.toolResult)
                } catch {
                    return .text(#"{"error":"Location unavailable: \#(error.localizedDescription)"}"#)
                }
            }
        ))
        HardwareTools.register()
        AstralTools.register()
        MathTools.register()
        ChartTools.register()
    }

    // MARK: - Window background fix

    /// On iOS 26 (Liquid Glass), UIHostingController uses a clear/transparent view
    /// so glass effects show through — but this leaves the raw UIWindow black on OLED.
    /// Setting rootViewController.view.backgroundColor is overridden by UIKit's drawing.
    ///
    /// The reliable fix: insert a plain UIView at z-index 0 inside the UIWindow itself,
    /// below everything SwiftUI and UIKit touch.  Its systemBackground color fills the
    /// Dynamic Island region (top) and home-indicator region (bottom) that would otherwise
    /// show the black window surface.  Tagged so we don't insert duplicates on re-fire.
    static func fixWindowBackgrounds() {
        applyWindowFix(label: "immediate")
        // Also run after layout has settled so we can see post-layout state in the log.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            applyWindowFix(label: "delayed-2s")
        }
    }

    @MainActor
    private static func applyWindowFix(label: String) {
        let tag = 0xEC01_B6 // "EcoBg" — unique sentinel
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let screenBounds = UIScreen.main.bounds
        fputs("[EcoBg:\(label)] \(scenes.count) scene(s) screenBounds=\(screenBounds)\n", stderr)
        for scene in scenes {
            for window in scene.windows {
                let winBg = window.backgroundColor.map { "\($0)" } ?? "nil"
                let rvBg  = window.rootViewController?.view.backgroundColor.map { "\($0)" } ?? "nil"
                fputs("[EcoBg:\(label)] window frame=\(window.frame) bg=\(winBg) rvBg=\(rvBg)\n", stderr)

                // Deep hierarchy dump so we can see what's actually rendering
                // in the safe-area bands (top ~59pt, bottom ~34pt).
                logViewHierarchy(window, prefix: "  ", label: label, maxDepth: 5)

                // 1. Window itself
                window.backgroundColor = .systemBackground
                // 2. rootViewController view
                window.rootViewController?.view.backgroundColor = .systemBackground
                // 3. Sentinel at z=0
                if window.viewWithTag(tag) == nil {
                    fputs("[EcoBg:\(label)] inserting sentinel\n", stderr)
                    let bg = UIView(frame: window.bounds)
                    bg.tag = tag
                    bg.backgroundColor = .systemBackground
                    bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    window.insertSubview(bg, at: 0)
                } else {
                    fputs("[EcoBg:\(label)] sentinel present\n", stderr)
                }
            }
        }
    }

    /// Recursive UIView hierarchy dump, capped at maxDepth.
    private static func logViewHierarchy(_ v: UIView, prefix: String, label: String, maxDepth: Int) {
        guard maxDepth > 0 else { return }
        let bg      = v.backgroundColor.map { "\($0)" } ?? "nil"
        let clips   = v.clipsToBounds ? " clips" : ""
        let hidden  = v.isHidden ? " HIDDEN" : ""
        let layerBg = v.layer.backgroundColor.map { UIColor(cgColor: $0).description } ?? "nil"
        fputs("[EcoBg:\(label)] \(prefix)\(type(of: v)) f=\(v.frame) bg=\(bg) layerBg=\(layerBg)\(clips)\(hidden)\n", stderr)
        for sv in v.subviews {
            logViewHierarchy(sv, prefix: prefix + "  ", label: label, maxDepth: maxDepth - 1)
        }
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
