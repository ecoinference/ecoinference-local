package ai.ecoinference.app.ui.auth

import androidx.compose.runtime.*
import ai.ecoinference.app.AppState
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.services.UserProfileService
import ai.ecoinference.app.ui.RootScreen

@Composable
fun AuthGateScreen(appState: AppState) {
    val currentUser by AuthService.currentUserFlow.collectAsState()

    LaunchedEffect(currentUser?.uid) {
        val uid = currentUser?.uid
        if (uid != null) {
            UserProfileService.startListening(uid)
        } else {
            UserProfileService.stopListening()
        }
    }

    if (currentUser != null) {
        RootScreen(appState)
    } else {
        SignInScreen()
    }
}
