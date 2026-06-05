package ai.ecoinference.app.ui

import android.Manifest
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.rememberMultiplePermissionsState
import ai.ecoinference.app.AppState
import ai.ecoinference.app.DeepLinkAction
import ai.ecoinference.app.ui.chat.ChatScreen
import ai.ecoinference.app.ui.models.ModelsScreen
import ai.ecoinference.app.ui.settings.SettingsScreen
import ai.ecoinference.app.ui.test.PythonTestScreen

private enum class Tab { Chat, Models, Tests, Settings }

/**
 * Requests all dangerous permissions required by agentic tools on first launch.
 *
 * Permissions covered:
 *   ACCESS_FINE_LOCATION   — get_location, show_map
 *   ACCESS_COARSE_LOCATION — fallback location
 *   CAMERA                 — toggle_torch, send_sos (flash)
 *   SEND_SMS               — send_sms
 *
 * The system dialog fires automatically on first run. If the user denies,
 * affected tools return a graceful {"error":"..."} JSON — the app itself
 * continues to function normally.
 */
@OptIn(ExperimentalPermissionsApi::class)
@Composable
private fun ToolPermissionsEffect() {
    val permissionsState = rememberMultiplePermissionsState(
        permissions = listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.CAMERA,
            Manifest.permission.SEND_SMS,
        )
    )
    LaunchedEffect(Unit) {
        permissionsState.launchMultiplePermissionRequest()
    }
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun RootScreen(appState: AppState) {
    var selectedTab by remember { mutableStateOf(Tab.Models) }
    val deepLink    by appState.deepLink.collectAsStateWithLifecycle()

    // Request dangerous permissions for agentic tools on first launch
    ToolPermissionsEffect()

    // Handle deep links
    LaunchedEffect(deepLink) {
        when (val dl = deepLink) {
            is DeepLinkAction.OpenChat     -> selectedTab = Tab.Chat
            is DeepLinkAction.OpenModels   -> selectedTab = Tab.Models
            is DeepLinkAction.OpenSettings -> selectedTab = Tab.Settings
            is DeepLinkAction.LoadModel    -> {
                selectedTab = Tab.Models
                appState.loadModel(dl.id)
            }
            else -> Unit
        }
        if (deepLink != null) appState.deepLink.value = null
    }

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.background) {
                NavigationBarItem(
                    selected  = selectedTab == Tab.Chat,
                    onClick   = { selectedTab = Tab.Chat },
                    icon      = { Icon(Icons.Default.Chat, contentDescription = "Chat") },
                    label     = { Text("Chat") },
                )
                NavigationBarItem(
                    selected  = selectedTab == Tab.Models,
                    onClick   = { selectedTab = Tab.Models },
                    icon      = { Icon(Icons.Default.SmartToy, contentDescription = "Models") },
                    label     = { Text("Models") },
                )
                NavigationBarItem(
                    selected  = selectedTab == Tab.Tests,
                    onClick   = { selectedTab = Tab.Tests },
                    icon      = { Icon(Icons.Default.Science, contentDescription = "Tests") },
                    label     = { Text("Tests") },
                )
                NavigationBarItem(
                    selected  = selectedTab == Tab.Settings,
                    onClick   = { selectedTab = Tab.Settings },
                    icon      = { Icon(Icons.Default.Settings, contentDescription = "Settings") },
                    label     = { Text("Settings") },
                )
            }
        }
    ) { innerPadding ->
        // Pass the bottom padding (= NavigationBar height) to each screen so
        // their content is never hidden behind the nav bar.
        when (selectedTab) {
            Tab.Chat     -> ChatScreen(appState, Modifier.padding(innerPadding))
            Tab.Models   -> ModelsScreen(appState, Modifier.padding(innerPadding))
            Tab.Tests    -> PythonTestScreen(appState, Modifier.padding(innerPadding))
            Tab.Settings -> SettingsScreen(appState, Modifier.padding(innerPadding))
        }
    }
}
