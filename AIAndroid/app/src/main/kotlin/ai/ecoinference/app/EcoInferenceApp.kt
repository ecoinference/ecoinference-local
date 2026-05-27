package ai.ecoinference.app

import android.app.Application
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.services.DownloadService
import ai.ecoinference.app.services.SettingsService
import ai.ecoinference.app.tools.AstralTools
import ai.ecoinference.app.tools.HardwareTools
import ai.ecoinference.app.tools.MathTools
import ai.ecoinference.app.tools.UrlTools

class EcoInferenceApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Pre-warm singletons
        SettingsService.getInstance(this)
        DownloadService.getInstance(this)
        InferenceService.getInstance(this)
        // Register agentic tools (no outbound internet — all on-device)
        HardwareTools.register(this)
        AstralTools.register()
        MathTools.register()
        UrlTools.register(this)
    }
}
