package com.gemma4.aiserver.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.gemma4.aiserver.R
import com.gemma4.aiserver.config.SettingsRepository
import com.gemma4.aiserver.download.DownloadRepository
import com.gemma4.aiserver.inference.InferenceRepository
import com.gemma4.aiserver.server.HttpServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import android.os.Process

/**
 * Headless foreground service that hosts the Ktor HTTP server.
 *
 * Lifecycle
 * ---------
 * START  → Intent with action [ACTION_START]  (sent by AIClient or the OS)
 * STOP   → Intent with action [ACTION_STOP]
 *
 * The service starts in the foreground immediately so Android does not kill
 * it. The HTTP server binds to 0.0.0.0:port so both loopback (emulator) and
 * LAN clients can reach it.
 *
 * Thread / coroutine model
 * -------------------------
 * All long-running work (downloads, model loading) is launched on
 * [serviceScope] which uses a [SupervisorJob] — a single failing child does
 * not cancel the scope.
 */
class AiServerService : Service() {

    companion object {
        const val ACTION_START = "com.gemma4.aiserver.ACTION_START"
        const val ACTION_STOP  = "com.gemma4.aiserver.ACTION_STOP"

        private const val TAG = "AiServerService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "ai_server_channel"
    }

    // ── Dependencies (lazy — created after context is available) ──────────────

    private val settings by lazy { SettingsRepository(applicationContext) }
    private val download by lazy { DownloadRepository(applicationContext) }
    private val inference by lazy { InferenceRepository(applicationContext) }

    /**
     * Supervisor-scoped coroutine scope tied to the service lifetime.
     * Cancelled in [onDestroy].
     */
    val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val httpServer by lazy {
        HttpServer(
            inference = inference,
            download = download,
            settings = settings,
            serviceScope = serviceScope,
        )
    }

    // ── Service lifecycle ─────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.i(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "Stop requested")
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                // ACTION_START or system restart — ensure we are in the foreground.
                startForeground(NOTIFICATION_ID, buildNotification(getString(R.string.notification_title_idle)))
                startServer()
            }
        }
        // Restart if killed by the OS so the server stays available.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null   // not a bound service

    override fun onDestroy() {
        Log.i(TAG, "Service destroying — stopping HTTP server and freeing model memory")
        httpServer.stop()
        inference.unload()
        serviceScope.cancel()
        super.onDestroy()
        // Kill the process so the OS reclaims native memory immediately.
        // stopSelf() stops the service but leaves the process alive as an empty
        // shell, and Android's native allocator does not return freed pages to
        // the OS until the process exits. For a server app that holds ~400 MB+
        // of native model weights this matters, so we exit explicitly.
        Log.i(TAG, "Killing process to return native memory to OS")
        Process.killProcess(Process.myPid())
    }

    // ── HTTP server ───────────────────────────────────────────────────────────

    private fun startServer() {
        serviceScope.launch {
            // Read the configured port from DataStore (suspending).
            val port = settings.port()
            Log.i(TAG, "Starting HTTP server on port $port")
            try {
                httpServer.start(port)
                updateNotification(getString(R.string.notification_title_running) + " :$port")
                Log.i(TAG, "HTTP server started on port $port")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start HTTP server: ${e.message}", e)
                updateNotification("AI Server — start failed")
            }
        }
    }

    // ── Notification helpers ──────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,  // silent — no sound/vibration
        ).apply {
            description = getString(R.string.notification_channel_desc)
        }
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(contentText: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_upload)   // placeholder icon
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    private fun updateNotification(contentText: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(contentText))
    }
}
