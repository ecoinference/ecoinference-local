package ai.ecoinference.app.tools

import kotlin.math.*

/**
 * On-device astronomical calculations — no network, no dependencies.
 *
 * Provides:
 *   get_moon_phase  — lunar phase name, illumination %, days into cycle
 *   get_sun_times   — sunrise, sunset, solar noon for a given lat/lon
 *   get_dawn_dusk   — civil and nautical twilight times
 *
 * Algorithms ported from the same sources used by Python's Astral library:
 *   - Moon phase: synodic period from J2000 reference new moon
 *   - Sun times:  Jean Meeus "Astronomical Algorithms" (USNO method)
 */
object AstralTools {

    fun register() {
        registerMoonPhase()
        registerSunTimes()
        registerDawnDusk()
    }

    // ── Moon phase ────────────────────────────────────────────────────────────

    private fun registerMoonPhase() {
        ToolRegistry.register(ToolDefinition(
            name          = "get_moon_phase",
            description   = "Returns the current lunar phase name, illumination percentage, and days into the cycle.",
            parametersDoc = "(no parameters — uses today's date)",
            argsExample   = "{}",
            execute       = { _ ->
                val result = moonPhase()
                ToolResult.Text("""{"phase":"${result.name}","illumination_pct":${result.illuminationPct},"days_into_cycle":${"%.1f".format(result.daysIntoCycle)},"days_to_full":${"%.1f".format(result.daysToFull)},"days_to_new":${"%.1f".format(result.daysToNew)}}""")
            }
        ))
    }

    private fun registerSunTimes() {
        ToolRegistry.register(ToolDefinition(
            name          = "get_sun_times",
            description   = "Returns sunrise, solar noon, and sunset times for the given coordinates and today's date.",
            parametersDoc = "latitude: number, longitude: number",
            argsExample   = "{\"latitude\":37.7749,\"longitude\":-122.4194}",
            execute       = { args ->
                val lat = extractDouble(args, "latitude")  ?: return@ToolDefinition ToolResult.Text("""{"error":"latitude required"}""")
                val lon = extractDouble(args, "longitude") ?: return@ToolDefinition ToolResult.Text("""{"error":"longitude required"}""")
                val tz  = java.util.TimeZone.getDefault()
                val cal = java.util.Calendar.getInstance(tz)
                val year  = cal.get(java.util.Calendar.YEAR)
                val month = cal.get(java.util.Calendar.MONTH) + 1
                val day   = cal.get(java.util.Calendar.DAY_OF_MONTH)
                val times = sunTimes(lat, lon, year, month, day, tz.rawOffset / 3600000.0)
                if (times == null) {
                    ToolResult.Text("""{"error":"Sun does not rise or set at this location on this date (polar day/night)"}""")
                } else {
                    ToolResult.Text("""{"sunrise":"${times.sunrise}","solar_noon":"${times.solarNoon}","sunset":"${times.sunset}","day_length_minutes":${times.dayLengthMinutes}}""")
                }
            }
        ))
    }

    private fun registerDawnDusk() {
        ToolRegistry.register(ToolDefinition(
            name          = "get_dawn_dusk",
            description   = "Returns civil dawn/dusk and nautical dawn/dusk for today at the given coordinates.",
            parametersDoc = "latitude: number, longitude: number",
            argsExample   = "{\"latitude\":37.7749,\"longitude\":-122.4194}",
            execute       = { args ->
                val lat = extractDouble(args, "latitude")  ?: return@ToolDefinition ToolResult.Text("""{"error":"latitude required"}""")
                val lon = extractDouble(args, "longitude") ?: return@ToolDefinition ToolResult.Text("""{"error":"longitude required"}""")
                val tz  = java.util.TimeZone.getDefault()
                val cal = java.util.Calendar.getInstance(tz)
                val year  = cal.get(java.util.Calendar.YEAR)
                val month = cal.get(java.util.Calendar.MONTH) + 1
                val day   = cal.get(java.util.Calendar.DAY_OF_MONTH)
                val tzOff = tz.rawOffset / 3600000.0
                val civil    = twilightTimes(lat, lon, year, month, day, tzOff, 6.0)
                val nautical = twilightTimes(lat, lon, year, month, day, tzOff, 12.0)
                ToolResult.Text("""{"civil_dawn":"${civil?.first ?: "N/A"}","civil_dusk":"${civil?.second ?: "N/A"}","nautical_dawn":"${nautical?.first ?: "N/A"}","nautical_dusk":"${nautical?.second ?: "N/A"}"}""")
            }
        ))
    }

    // ── Moon phase math ───────────────────────────────────────────────────────

    private data class MoonPhaseResult(
        val name: String,
        val illuminationPct: Int,
        val daysIntoCycle: Double,
        val daysToFull: Double,
        val daysToNew: Double,
    )

    private fun moonPhase(): MoonPhaseResult {
        // Reference new moon: 6 Jan 2000 18:14 UTC (J2000 epoch reference)
        val refNewMoonJd = 2451549.5 + 0.759722 // JD of Jan 6 2000 new moon

        val nowJd = currentJulianDay()
        val synodicPeriod = 29.53058868

        val daysSinceRef = nowJd - refNewMoonJd
        val cycle = ((daysSinceRef % synodicPeriod) + synodicPeriod) % synodicPeriod

        // Illumination: cos-based (0 at new, 1 at full, 0 at new again)
        val angle = cycle / synodicPeriod * 2 * PI
        val illumination = ((1 - cos(angle)) / 2 * 100).roundToInt().coerceIn(0, 100)

        val name = when {
            cycle < 1.85  -> "New Moon"
            cycle < 7.38  -> "Waxing Crescent"
            cycle < 9.22  -> "First Quarter"
            cycle < 14.77 -> "Waxing Gibbous"
            cycle < 16.61 -> "Full Moon"
            cycle < 22.15 -> "Waning Gibbous"
            cycle < 24.0  -> "Last Quarter"
            else           -> "Waning Crescent"
        }

        val daysToFull = if (cycle < 14.77) 14.77 - cycle
                         else synodicPeriod - cycle + 14.77
        val daysToNew  = synodicPeriod - cycle

        return MoonPhaseResult(name, illumination, cycle, daysToFull, daysToNew)
    }

    // ── Sun times math (Jean Meeus method) ───────────────────────────────────

    private data class SunTimesResult(
        val sunrise: String,
        val solarNoon: String,
        val sunset: String,
        val dayLengthMinutes: Int,
    )

    /**
     * Returns sunrise/noon/sunset as "HH:mm" local time strings, or null for
     * polar day/night. [tzOffset] is hours east of UTC (e.g. -8 for PST).
     */
    private fun sunTimes(
        lat: Double, lon: Double,
        year: Int, month: Int, day: Int,
        tzOffset: Double,
    ): SunTimesResult? {
        val rise = sunEvent(lat, lon, year, month, day, tzOffset, rising = true,  zenith = 90.833) ?: return null
        val set  = sunEvent(lat, lon, year, month, day, tzOffset, rising = false, zenith = 90.833) ?: return null
        val noon = (rise + set) / 2.0
        val dayLen = ((set - rise) * 60).roundToInt()
        return SunTimesResult(
            sunrise          = decimalHoursToHHmm(rise),
            solarNoon        = decimalHoursToHHmm(noon),
            sunset           = decimalHoursToHHmm(set),
            dayLengthMinutes = dayLen,
        )
    }

    private fun twilightTimes(
        lat: Double, lon: Double,
        year: Int, month: Int, day: Int,
        tzOffset: Double,
        depression: Double,
    ): Pair<String, String>? {
        val zenith = 90.0 + depression
        val dawn = sunEvent(lat, lon, year, month, day, tzOffset, rising = true,  zenith = zenith) ?: return null
        val dusk = sunEvent(lat, lon, year, month, day, tzOffset, rising = false, zenith = zenith) ?: return null
        return decimalHoursToHHmm(dawn) to decimalHoursToHHmm(dusk)
    }

    /**
     * USNO sunrise/sunset algorithm.
     * Returns local time as decimal hours, or null for polar day/night.
     */
    private fun sunEvent(
        lat: Double, lon: Double,
        year: Int, month: Int, day: Int,
        tzOffset: Double,
        rising: Boolean,
        zenith: Double,
    ): Double? {
        // Day of year
        val n1 = floor(275.0 * month / 9)
        val n2 = floor((month + 9.0) / 12)
        val n3 = 1 + floor((year - 4 * floor(year / 4.0) + 2) / 3)
        val n  = n1 - n2 * n3 + day - 30

        // Approximate time of event
        val lngHour = lon / 15.0
        val t = if (rising) n + (6 - lngHour) / 24.0
                else         n + (18 - lngHour) / 24.0

        // Mean anomaly
        val m = (0.9856 * t - 3.289).toRad()

        // Sun's true longitude
        var l = m.toDeg() + 1.916 * sin(m) + 0.020 * sin(2 * m) + 282.634
        l = l.normDeg()

        // Sun's right ascension
        var ra = atan(0.91764 * tan(l.toRad())).toDeg()
        ra = ra.normDeg()
        val lQuad  = floor(l  / 90) * 90
        val raQuad = floor(ra / 90) * 90
        ra = (ra + lQuad - raQuad) / 15.0

        // Sun's declination
        val sinDec = 0.39782 * sin(l.toRad())
        val cosDec = cos(asin(sinDec))

        // Local hour angle
        val cosH = (cos(zenith.toRad()) - sinDec * sin(lat.toRad())) /
                   (cosDec * cos(lat.toRad()))
        if (cosH < -1) return null // never sets (polar day)
        if (cosH > 1)  return null // never rises (polar night)

        val h = if (rising) 360 - acos(cosH).toDeg()
                else         acos(cosH).toDeg()
        val hh = h / 15.0

        // Local mean time of rising/setting
        val t2 = hh + ra - 0.06571 * t - 6.622
        // Adjust to UTC, then local time
        var ut = t2 - lngHour + tzOffset
        ut = ((ut % 24) + 24) % 24
        return ut
    }

    // ── Julian Day ────────────────────────────────────────────────────────────

    private fun currentJulianDay(): Double {
        val ms = System.currentTimeMillis()
        return ms / 86400000.0 + 2440587.5
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun Double.toRad() = this * PI / 180.0
    private fun Double.toDeg() = this * 180.0 / PI
    private fun Double.normDeg(): Double = ((this % 360) + 360) % 360

    private fun decimalHoursToHHmm(h: Double): String {
        val total = ((h % 24) + 24) % 24
        val hh    = total.toInt()
        val mm    = ((total - hh) * 60).roundToInt().coerceIn(0, 59)
        return "%02d:%02d".format(hh, mm)
    }

    private fun extractDouble(args: String, key: String): Double? {
        val match = Regex("\"$key\"\\s*:\\s*(-?[0-9.]+)").find(args)
        return match?.groupValues?.get(1)?.toDoubleOrNull()
    }
}
