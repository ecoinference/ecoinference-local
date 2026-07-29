package ai.ecoinference.app.services

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.Tasks
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Builds a Python preamble assigning the device's GPS coordinates and
 * timezone to pre-defined variables, for code-generation prompts that need
 * the user's current location/local time (e.g. astral/sun calculations).
 *
 * Extracted from PythonTestScreen.kt (2026-07-28) so the `use tool` command
 * can share it rather than duplicating the fetch/fallback logic.
 */
object LocationPreamble {

    private const val TAG = "LocationPreamble"

    @SuppressLint("MissingPermission")
    suspend fun fetch(context: Context): String =
        withContext(Dispatchers.IO) {
            try {
                val client = LocationServices.getFusedLocationProviderClient(context)
                val loc    = Tasks.await(
                    client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null),
                    5, TimeUnit.SECONDS,
                )
                val tz     = TimeZone.getDefault()
                val offset = tz.rawOffset / 3_600_000.0
                if (loc != null)
                    build(loc.latitude, loc.longitude, tz.id, offset)
                else
                    default()
            } catch (e: Exception) {
                Log.w(TAG, "GPS unavailable, using fallback coords: ${e.message}")
                default()
            }
        }

    fun build(lat: Double, lon: Double, tzId: String, tzOffset: Double) =
        "user_latitude = $lat\nuser_longitude = $lon\nuser_timezone = \"$tzId\"\nuser_timezone_offset = $tzOffset\n"

    fun default() =
        build(41.8450, -91.7026, "America/Chicago", -6.0)
}
