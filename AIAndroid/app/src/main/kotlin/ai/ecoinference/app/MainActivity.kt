package ai.ecoinference.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import ai.ecoinference.app.ui.auth.AuthGateScreen
import ai.ecoinference.app.ui.theme.EcoInferenceTheme

class MainActivity : ComponentActivity() {

    private val appState: AppState by viewModels { AppState.factory(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        setContent {
            EcoInferenceTheme {
                AuthGateScreen(appState)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    // ── Deep link / URL scheme handler ────────────────────────────────────────
    //
    // Supported URLs (mirrors iOS AIServeriOSApp.swift handleURL):
    //   ecoinference://chat
    //   ecoinference://chat?message=<text>&send=1&system=<text>
    //   ecoinference://models
    //   ecoinference://models/load?id=<model_id>
    //   ecoinference://settings
    //   ecoinference://x-callback-url/infer?prompt=<text>&x-success=<url>

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme?.lowercase() != "ecoinference") return

        val host  = uri.host?.lowercase() ?: ""
        val path  = uri.path?.lowercase() ?: ""

        appState.deepLink.value = when (host) {
            "chat" -> DeepLinkAction.OpenChat(
                prefill      = uri.getQueryParameter("message"),
                autoSend     = uri.getQueryParameter("send") == "1",
                systemPrompt = uri.getQueryParameter("system"),
            )
            "models" -> {
                if (path.startsWith("/load")) {
                    val id = uri.getQueryParameter("id")
                    if (id != null) DeepLinkAction.LoadModel(id) else DeepLinkAction.OpenModels
                } else {
                    DeepLinkAction.OpenModels
                }
            }
            "settings" -> DeepLinkAction.OpenSettings
            "x-callback-url" -> {
                if (path.startsWith("/infer")) {
                    val prompt = uri.getQueryParameter("prompt") ?: return
                    DeepLinkAction.BackgroundInfer(
                        prompt      = prompt,
                        callbackUrl = uri.getQueryParameter("x-success"),
                    )
                } else null
            }
            else -> null
        }
    }
}
