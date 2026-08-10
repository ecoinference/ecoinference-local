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

    /**
     * Python preamble prepended to every generated snippet. Must stay in sync with
     * iOS's LocationService.pythonPreamble — the code-gen prompt describes one
     * contract to the model and both platforms have to honour it.
     *
     * Two things here are load-bearing:
     *
     *  - `datetime` is imported *unaliased*. The prompt tells the model to call
     *    `datetime.date.today()`, and models routinely emit that without also
     *    emitting `import datetime` — which used to fail with
     *    "NameError: name 'datetime' is not defined" (seen live on E4B for the
     *    Help screen's moon-phase example). Binding it here makes the generated
     *    code work whether or not the model remembers the import.
     *  - `user_timezone` is a real tzinfo, not a string. The prompt documents it
     *    as `tzinfo` and astral is called as `sun(..., tzinfo=user_timezone)`;
     *    this used to emit the zone *name* as a string, so any such call broke on
     *    Android while working on iOS. Built from the raw offset rather than
     *    zoneinfo, which needs tzdata that isn't bundled.
     */
    fun build(lat: Double, lon: Double, tzId: String, tzOffset: Double) = """
        user_latitude = $lat
        user_longitude = $lon
        user_timezone_offset = $tzOffset
        user_timezone_name = "$tzId"
        import datetime
        import datetime as _dt
        user_timezone = _dt.timezone(_dt.timedelta(hours=$tzOffset))
    """.trimIndent() + "\n"

    fun default() =
        build(41.8450, -91.7026, "America/Chicago", -6.0)
}
