package ai.ecoinference.app

import android.app.Application
import com.chaquo.python.android.AndroidPlatform
import com.chaquo.python.Python
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.services.DownloadService
import ai.ecoinference.app.services.SettingsService
import ai.ecoinference.app.tools.AstralTools
import ai.ecoinference.app.tools.ChartTools
import ai.ecoinference.app.tools.HardwareTools
import ai.ecoinference.app.tools.ImageEditTools
import ai.ecoinference.app.tools.MathTools
import ai.ecoinference.app.tools.PythonTools
import ai.ecoinference.app.tools.QrCodeTools
import ai.ecoinference.app.tools.UrlTools

class EcoInferenceApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Start Chaquopy (native CPython) — must happen before any Python call
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        // Pre-warm singletons
        SettingsService.getInstance(this)
        DownloadService.getInstance(this)
        InferenceService.getInstance(this)
        // Register agentic tools (no outbound internet — all on-device)
        HardwareTools.register(this)
        AstralTools.register()
        MathTools.register()
        ChartTools.register()
        UrlTools.register(this)
        PythonTools.register()
        ImageEditTools.register()
        QrCodeTools.register()
    }
}
