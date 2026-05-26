package ai.ecoinference.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.ecoinference.app.AppState
import ai.ecoinference.app.DeepLinkAction
import ai.ecoinference.app.ui.chat.ChatScreen
import ai.ecoinference.app.ui.models.ModelsScreen
import ai.ecoinference.app.ui.settings.SettingsScreen

private enum class Tab { Chat, Models, Settings }

@Composable
fun RootScreen(appState: AppState) {
    var selectedTab by remember { mutableStateOf(Tab.Chat) }
    val deepLink    by appState.deepLink.collectAsStateWithLifecycle()

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
            Tab.Settings -> SettingsScreen(appState, Modifier.padding(innerPadding))
        }
    }
}
