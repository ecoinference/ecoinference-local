package com.gemma4.aiserver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.gemma4.aiserver.service.AiServerService

/**
 * BroadcastReceiver entry-point for AIClient.
 *
 * AIClient cannot call [Context.startForegroundService] directly — it uses
 * [android_intent_plus] which only supports [startActivity] and
 * [sendBroadcast]. This receiver bridges the gap: it receives the broadcast
 * and immediately forwards it to [AiServerService] via
 * [startForegroundService], which is always permitted from a receiver.
 *
 * Registered as exported in AndroidManifest so AIClient can reach it by
 * package + component name across the process boundary.
 */
class ServerControlReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.i(TAG, "Received: $action")

        val serviceIntent = Intent(context, AiServerService::class.java).apply {
            this.action = action
        }
        // startForegroundService is always allowed from a BroadcastReceiver,
        // regardless of whether the app is in the background.
        context.startForegroundService(serviceIntent)
    }

    companion object {
        private const val TAG = "ServerControlReceiver"
    }
}
