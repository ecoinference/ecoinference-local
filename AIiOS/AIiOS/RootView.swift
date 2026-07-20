import SwiftUI

/// Top-level tab container.
/// Default tab is Models. Loading a model auto-navigates to Chat once it
/// finishes (AppState.loadModel sets deepLink = .openChat() on success).
struct RootView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authService: AuthService
    @State private var selectedTab: Tab = .models

    enum Tab { case chat, models, profile, settings }

    var body: some View {
        // .ignoresSafeArea() on the ZStack makes its LAYOUT frame = full screen
        // (not just the safe-area-inset region).  Color therefore fills the full
        // screen without needing to extend beyond any drawing-context bounds.
        // On iOS 26 (Liquid Glass) SwiftUI may clip a child's rendering to the
        // parent ZStack's drawing context; putting ignoresSafeArea on the
        // container avoids that entirely.
        ZStack {
            EcoColors.background
            TabView(selection: $selectedTab) {

                ChatView()
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                    .tag(Tab.chat)

                ModelsView()
                    .tabItem { Label("Models", systemImage: "cpu") }
                    .tag(Tab.models)

                ProfileView()
                    .environmentObject(authService)
                    .tabItem { Label("Profile", systemImage: "person.circle") }
                    .tag(Tab.profile)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .toolbarBackground(.visible, for: .tabBar)
        }
        .ignoresSafeArea()
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
