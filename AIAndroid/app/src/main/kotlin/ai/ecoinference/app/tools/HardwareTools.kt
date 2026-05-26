package ai.ecoinference.app.tools

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.BatteryManager
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.Tasks
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.TimeZone

/**
 * Registers hardware-access tools: location, battery, torch.
 * Mirrors iOS HardwareTools registration in AIServeriOSApp.swift.
 */
object HardwareTools {

    fun register(context: Context) {
        registerLocation(context)
        registerBattery(context)
        registerTorch(context)
    }

    // ── Location ──────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun registerLocation(context: Context) {
        ToolRegistry.register(ToolDefinition(
            name          = "get_location",
            description   = "Returns the device's current GPS coordinates and timezone.",
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
                            """{"latitude":${location.latitude},"longitude":${location.longitude},"timezone":"${TimeZone.getDefault().id}"}"""
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
                val intent    = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val level     = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale     = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                val status    = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val pct       = if (level >= 0 && scale > 0) level * 100 / scale else -1
                val charging  = status == BatteryManager.BATTERY_STATUS_CHARGING ||
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
                    val target = if (args.contains("\"on\":true")) true
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
}
