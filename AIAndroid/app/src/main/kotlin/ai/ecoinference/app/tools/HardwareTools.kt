package ai.ecoinference.app.tools

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.BatteryManager
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.Tasks
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.TimeZone

/**
 * Registers hardware-access tools: location, battery, torch, SOS, map, SMS.
 */
object HardwareTools {

    fun register(context: Context) {
        registerLocation(context)
        registerBattery(context)
        registerTorch(context)
        registerSos(context)
        registerShowMap(context)
        registerSendSms(context)
    }

    // ── Location ──────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun registerLocation(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "get_location",
            description   = "Returns the device's current GPS coordinates, altitude, and timezone.",
            parametersDoc = "(no parameters)",
            argsExample   = "{}",
            execute       = { _ ->
                withContext(Dispatchers.IO) {
                    try {
                        val client   = LocationServices.getFusedLocationProviderClient(context)
                        val location = Tasks.await(
                            client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
                        )
                        if (location != null) {
                            """{"latitude":${location.latitude},"longitude":${location.longitude},"altitude":${location.altitude},"timezone":"${TimeZone.getDefault().id}"}"""
                        } else {
                            """{"error":"Location unavailable"}"""
                        }
                    } catch (e: Exception) {
                        """{"error":"${e.message}"}"""
                    }
                }
            }
        ))
    }

    // ── Battery ───────────────────────────────────────────────────────────────

    private fun registerBattery(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "get_battery",
            description   = "Returns the device battery level (0–100) and charging status.",
            parametersDoc = "(no parameters)",
            argsExample   = "{}",
            execute       = { _ ->
                val intent   = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val level    = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale    = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                val status   = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val pct      = if (level >= 0 && scale > 0) level * 100 / scale else -1
                val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                               status == BatteryManager.BATTERY_STATUS_FULL
                """{"level":$pct,"charging":$charging}"""
            }
        ))
    }

    // ── Torch ─────────────────────────────────────────────────────────────────

    private fun registerTorch(context: Context) {
        var torchOn = false
        ToolRegistry.register(ToolDefinition(
            name          = "toggle_torch",
            description   = "Toggles the device flashlight on or off.",
            parametersDoc = "on: boolean (optional — if omitted, toggles current state)",
            argsExample   = "{\"on\":true}",
            execute       = { args ->
                try {
                    val target     = if (args.contains("\"on\":true")) true
                                    else if (args.contains("\"on\":false")) false
                                    else !torchOn
                    val mgr        = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId   = mgr.cameraIdList.firstOrNull { id ->
                        mgr.getCameraCharacteristics(id)
                            .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                    }
                    if (cameraId != null) {
                        mgr.setTorchMode(cameraId, target)
                        torchOn = target
                        """{"torch":$target}"""
                    } else {
                        """{"error":"No torch available"}"""
                    }
                } catch (e: Exception) {
                    """{"error":"${e.message}"}"""
                }
            }
        ))
    }

    // ── SOS ───────────────────────────────────────────────────────────────────

    /**
     * Flashes SOS in ITU Morse code (· · · — — — · · ·) using the torch.
     * Timing: dot=200ms, dash=600ms, symbol gap=200ms, letter gap=600ms.
     */
    private fun registerSos(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "send_sos",
            description   = "Flashes the SOS Morse code (· · · — — — · · ·) using the device torch.",
            parametersDoc = "(no parameters)",
            argsExample   = "{}",
            execute       = { _ ->
                withContext(Dispatchers.IO) {
                    try {
                        val mgr      = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val cameraId = mgr.cameraIdList.firstOrNull { id ->
                            mgr.getCameraCharacteristics(id)
                                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                        } ?: return@withContext """{"error":"No torch available"}"""

                        // (on_ms, off_ms) — 0 off_ms = no trailing gap on last symbol
                        val sos = listOf(
                            // S: · · ·
                            200L to 200L, 200L to 200L, 200L to 600L,
                            // O: — — —
                            600L to 200L, 600L to 200L, 600L to 600L,
                            // S: · · ·
                            200L to 200L, 200L to 200L, 200L to 0L,
                        )
                        for ((on, off) in sos) {
                            mgr.setTorchMode(cameraId, true)
                            delay(on)
                            mgr.setTorchMode(cameraId, false)
                            if (off > 0) delay(off)
                        }
                        """{"result":"SOS signal complete (· · · — — — · · ·)"}"""
                    } catch (e: Exception) {
                        """{"error":"${e.message}"}"""
                    }
                }
            }
        ))
    }

    // ── Show map ──────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun registerShowMap(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "show_map",
            description   = "Gets the current GPS location and opens it in the device maps app.",
            parametersDoc = "(no parameters)",
            argsExample   = "{}",
            execute       = { _ ->
                withContext(Dispatchers.IO) {
                    try {
                        val client   = LocationServices.getFusedLocationProviderClient(context)
                        val location = Tasks.await(
                            client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
                        )
                        if (location == null) return@withContext """{"error":"Location unavailable"}"""

                        val lat = location.latitude
                        val lon = location.longitude
                        val uri = Uri.parse("geo:$lat,$lon?q=$lat,$lon&z=17")
                        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        """{"result":"Map opened","latitude":$lat,"longitude":$lon}"""
                    } catch (e: Exception) {
                        """{"error":"${e.message}"}"""
                    }
                }
            }
        ))
    }

    // ── Send SMS ──────────────────────────────────────────────────────────────

    private fun registerSendSms(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "send_sms",
            description   = "Opens the SMS composer with a pre-filled recipient and message. User must tap Send.",
            parametersDoc = "to: string (phone number), message: string",
            argsExample   = "{\"to\":\"+15551234567\",\"message\":\"Hello!\"}",
            execute       = { args ->
                val toMatch  = Regex("\"to\"\\s*:\\s*\"(.*?)\"").find(args)
                val msgMatch = Regex("\"message\"\\s*:\\s*\"(.*?)\"", RegexOption.DOT_MATCHES_ALL).find(args)
                val to       = toMatch?.groupValues?.get(1)?.trim() ?: ""
                val message  = msgMatch?.groupValues?.get(1)?.trim() ?: ""
                if (to.isBlank())      return@ToolDefinition """{"error":"'to' is required"}"""
                if (message.isBlank()) return@ToolDefinition """{"error":"'message' is required"}"""
                try {
                    val uri    = Uri.parse("smsto:$to")
                    val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                        putExtra("sms_body", message)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    """{"result":"SMS composer opened for $to"}"""
                } catch (e: Exception) {
                    """{"error":"${e.message}"}"""
                }
            }
        ))
    }
}
