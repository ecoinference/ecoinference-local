package com.gemma4.aiserver

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.gemma4.aiserver.service.AiServerService

/**
 * Transparent trampoline Activity — zero UI, finishes before first frame.
 *
 * Why this exists
 * ───────────────
 * On Android 12+ the OS blocks startForegroundService() from any context
 * that lacks a foreground-service-launch allowance (BFSL).  A
 * BroadcastReceiver triggered by a cross-app broadcast does NOT receive
 * BFSL on Android 14+ / API 34+ (confirmed ForegroundServiceStartNotAllowed-
 * Exception on API 36).  An Activity that is being started DOES receive BFSL
 * while it is running, so this pattern is the only fully reliable way for
 * AIClient to start AiServerService from the foreground.
 *
 * Flow
 * ────
 * 1. AIClient (in foreground) calls intent.launch() targeting this Activity.
 * 2. Android starts the Activity; it immediately calls startForegroundService
 *    (always allowed while an Activity is executing onCreate) and finish().
 * 3. User never sees any UI — the Activity closes before a frame is drawn.
 */
class StartServerActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val action = intent?.action ?: AiServerService.ACTION_START
        val serviceIntent = Intent(this, AiServerService::class.java).apply {
            this.action = action
        }

        when (action) {
            AiServerService.ACTION_STOP -> startService(serviceIntent)
            else                        -> startForegroundService(serviceIntent)
        }

        finish()
    }
}
