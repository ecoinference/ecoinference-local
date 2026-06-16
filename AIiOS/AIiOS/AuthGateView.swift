import SwiftUI

/// Routes to SignInView or the main app depending on Firebase Auth state.
struct AuthGateView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        Group {
            if authService.currentUser != nil {
                RootView()
            } else {
                SignInView()
            }
        }
        .onAppear {
            if let uid = authService.currentUser?.uid {
                UserProfileService.shared.startListening(uid: uid)
            }
        }
        .onChange(of: authService.currentUser?.uid) { _, uid in
            if let uid {
                UserProfileService.shared.startListening(uid: uid)
            } else {
                UserProfileService.shared.stopListening()
            }
        }
    }
}
