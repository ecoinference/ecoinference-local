package com.gemma4.aiserver

import android.app.Application
import android.util.Log

/**
 * Application entry-point.
 *
 * Kept intentionally thin — all repository construction is deferred to
 * [com.gemma4.aiserver.service.AiServerService] so that nothing is
 * instantiated until the service is actually started.
 *
 * Extend this class only for app-wide singletons that must exist before
 * the first component (Activity, Service, BroadcastReceiver) launches,
 * e.g. a crash-reporting SDK.
 */
class AiServerApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        Log.i("AiServerApp", "Application created — headless AI server")
    }
}
