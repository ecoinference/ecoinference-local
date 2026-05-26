package ai.ecoinference.app

import android.app.Application
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.services.DownloadService
import ai.ecoinference.app.services.SettingsService
import ai.ecoinference.app.tools.HardwareTools
import ai.ecoinference.app.tools.UrlTools
import ai.ecoinference.app.tools.WebSearchTool

class EcoInferenceApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Pre-warm singletons
        SettingsService.getInstance(this)
        DownloadService.getInstance(this)
        InferenceService.getInstance(this)
        // Register agentic tools
        HardwareTools.register(this)
        WebSearchTool.register()
        UrlTools.register(this)
    }
}
