import SwiftUI

/// Top-level tab container.
/// Default tab is Models (Option C) — the user explicitly navigates to Chat
/// once a model is loaded.
struct RootView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .models

    enum Tab { case chat, models, settings }

    var body: some View {
        TabView(selection: $selectedTab) {

            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chat)

            ModelsView()
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(Tab.models)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // ── Deep link routing ─────────────────────────────────────────────────
        .onChange(of: appState.deepLink) { _, action in
            guard let action else { return }
            switch action {
            case .openChat, .backgroundInfer:
                selectedTab = .chat
            case .openModels:
                selectedTab = .models
            case .openSettings:
                selectedTab = .settings
            case .loadModel(let id):
                selectedTab = .models
                appState.loadModel(modelId: id)
            }
            // Clear after handling so repeated identical links re-trigger.
            Task { @MainActor in appState.deepLink = nil }
        }
    }
}
