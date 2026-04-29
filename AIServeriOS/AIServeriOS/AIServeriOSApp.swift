import SwiftUI

@main
struct AIServeriOSApp: App {

    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    // MARK: - URL scheme  (aiserver://start | aiserver://stop)

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "aiserver" else { return }

        switch url.host?.lowercased() {
        case "start":
            if !appState.serverRunning {
                appState.startServer()
            }
        case "stop":
            // Unload the model first so native memory is returned to the OS
            // before the HTTP listener closes and the process goes idle.
            if appState.modelLoaded {
                appState.unloadModel()
            }
            if appState.serverRunning {
                appState.stopServer()
            }
        default:
            break
        }
    }
}
