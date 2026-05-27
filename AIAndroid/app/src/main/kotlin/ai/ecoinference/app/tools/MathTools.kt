package ai.ecoinference.app.tools

import org.apache.commons.math3.analysis.polynomials.PolynomialFunction
import org.apache.commons.math3.fitting.PolynomialCurveFitter
import org.apache.commons.math3.fitting.WeightedObservedPoints
import org.apache.commons.math3.stat.descriptive.DescriptiveStatistics
import org.apache.commons.math3.transform.DftNormalization
import org.apache.commons.math3.transform.FastFourierTransformer
import org.apache.commons.math3.transform.TransformType
import kotlin.math.*

/**
 * On-device math and signal processing tools backed by Apache Commons Math 3.
 * No network calls, no Python, fully offline.
 *
 * Tools:
 *   compute_stats  — descriptive statistics (mean, median, std dev, percentiles)
 *   run_fft        — Fast Fourier Transform, returns dominant frequencies
 *   fit_curve      — polynomial curve fitting (linear, quadratic, cubic)
 *   compute_geometry — GPS distance (Haversine), polygon area, bearing
 */
object MathTools {

    fun register() {
        registerStats()
        registerFft()
        registerFitCurve()
        registerGeometry()
    }

    // ── Descriptive statistics ────────────────────────────────────────────────

    private fun registerStats() {
        ToolRegistry.register(ToolDefinition(
            name          = "compute_stats",
            description   = "Computes descriptive statistics for a list of numbers: mean, median, std dev, min, max, and percentiles.",
            parametersDoc = "data: array of numbers",
            argsExample   = "{\"data\":[1,2,3,4,5,6,7,8,9,10]}",
            execute       = { args ->
                val data = parseDoubleArray(args, "data")
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'data' must be a JSON array of numbers"}""")
                if (data.isEmpty()) return@ToolDefinition ToolResult.Text("""{"error":"data array is empty"}""")

                val stats = DescriptiveStatistics(data.toDoubleArray())
                ToolResult.Text("""{"count":${stats.n},"mean":${"%.4f".format(stats.mean)},"median":${"%.4f".format(stats.getPercentile(50.0))},"std_dev":${"%.4f".format(stats.standardDeviation)},"variance":${"%.4f".format(stats.variance)},"min":${stats.min},"max":${stats.max},"p25":${"%.4f".format(stats.getPercentile(25.0))},"p75":${"%.4f".format(stats.getPercentile(75.0))},"p90":${"%.4f".format(stats.getPercentile(90.0))}}""")
            }
        ))
    }

    // ── FFT ───────────────────────────────────────────────────────────────────

    private fun registerFft() {
        ToolRegistry.register(ToolDefinition(
            name          = "run_fft",
            description   = "Runs a Fast Fourier Transform on a data array. Returns the top dominant frequency components and their magnitudes. Provide sample_rate_hz to get frequency in Hz.",
            parametersDoc = "data: array of numbers, sample_rate_hz: number (optional, default 1.0), top_n: number (optional, default 5)",
            argsExample   = "{\"data\":[0,1,0,-1,0,1,0,-1],\"sample_rate_hz\":8.0,\"top_n\":3}",
            execute       = { args ->
                val rawData    = parseDoubleArray(args, "data")
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'data' must be a JSON array of numbers"}""")
                val sampleRate = extractDouble(args, "sample_rate_hz") ?: 1.0
                val topN       = extractInt(args, "top_n") ?: 5

                if (rawData.size < 2) return@ToolDefinition ToolResult.Text("""{"error":"data must have at least 2 elements"}""")

                // Pad to next power of two (FFT requirement)
                val n    = nextPowerOfTwo(rawData.size)
                val data = DoubleArray(n) { if (it < rawData.size) rawData[it] else 0.0 }

                val fft        = FastFourierTransformer(DftNormalization.STANDARD)
                val complex    = fft.transform(data, TransformType.FORWARD)
                val halfN      = n / 2

                // Compute magnitudes and frequencies
                data class FreqBin(val freqHz: Double, val magnitude: Double)
                val bins = (1 until halfN).map { k ->
                    val mag  = complex[k].abs() / n
                    val freq = k * sampleRate / n
                    FreqBin(freq, mag)
                }.sortedByDescending { it.magnitude }.take(topN)

                val binsJson = bins.joinToString(",") {
                    "{\"freq_hz\":${"%.4f".format(it.freqHz)},\"magnitude\":${"%.4f".format(it.magnitude)}}"
                }
                ToolResult.Text("""{"n_samples":${rawData.size},"n_padded":$n,"sample_rate_hz":$sampleRate,"top_frequencies":[$binsJson]}""")
            }
        ))
    }

    // ── Curve fitting ─────────────────────────────────────────────────────────

    private fun registerFitCurve() {
        ToolRegistry.register(ToolDefinition(
            name          = "fit_curve",
            description   = "Fits a polynomial curve to x,y data points. Returns coefficients and R² goodness-of-fit.",
            parametersDoc = "x: array of numbers, y: array of numbers, degree: number (1=linear, 2=quadratic, 3=cubic; default 1)",
            argsExample   = "{\"x\":[1,2,3,4,5],\"y\":[2.1,3.9,6.2,7.8,10.1],\"degree\":1}",
            execute       = { args ->
                val x      = parseDoubleArray(args, "x") ?: return@ToolDefinition ToolResult.Text("""{"error":"'x' required"}""")
                val y      = parseDoubleArray(args, "y") ?: return@ToolDefinition ToolResult.Text("""{"error":"'y' required"}""")
                val degree = extractInt(args, "degree") ?: 1

                if (x.size != y.size) return@ToolDefinition ToolResult.Text("""{"error":"x and y must have the same length"}""")
                if (x.size < degree + 1) return@ToolDefinition ToolResult.Text("""{"error":"need at least degree+1 data points"}""")
                if (degree < 1 || degree > 5) return@ToolDefinition ToolResult.Text("""{"error":"degree must be 1–5"}""")

                val obs = WeightedObservedPoints()
                x.zip(y).forEach { (xi, yi) -> obs.add(xi, yi) }

                val fitter  = PolynomialCurveFitter.create(degree)
                val coeffs  = fitter.fit(obs.toList())   // [c0, c1, c2, ...] lowest order first
                val poly    = PolynomialFunction(coeffs)

                // R² = 1 - SS_res / SS_tot
                val yMean  = y.average()
                val ssTot  = y.sumOf { (it - yMean).pow(2) }
                val ssRes  = x.zip(y).sumOf { (xi, yi) -> (yi - poly.value(xi)).pow(2) }
                val r2     = if (ssTot == 0.0) 1.0 else 1.0 - ssRes / ssTot

                val degreeLabel = when (degree) { 1 -> "linear"; 2 -> "quadratic"; 3 -> "cubic"; else -> "degree-$degree" }
                val coeffJson   = coeffs.mapIndexed { i, c -> "\"c$i\":${"%.6f".format(c)}" }.joinToString(",")
                ToolResult.Text("""{"degree":$degree,"type":"$degreeLabel","coefficients":{$coeffJson},"r_squared":${"%.4f".format(r2)},"equation":"${polyEquation(coeffs)}"}""")
            }
        ))
    }

    // ── Geometry ──────────────────────────────────────────────────────────────

    private fun registerGeometry() {
        ToolRegistry.register(ToolDefinition(
            name          = "compute_geometry",
            description   = "Computes GPS distance between two points (Haversine), bearing, and optionally the area of a polygon defined by lat/lon coordinates.",
            parametersDoc = "operation: \"distance\"|\"bearing\"|\"polygon_area\". For distance/bearing: lat1,lon1,lat2,lon2. For polygon_area: points array of {lat,lon}.",
            argsExample   = "{\"operation\":\"distance\",\"lat1\":37.7749,\"lon1\":-122.4194,\"lat2\":34.0522,\"lon2\":-118.2437}",
            execute       = { args ->
                val op = Regex("\"operation\"\\s*:\\s*\"([^\"]+)\"").find(args)?.groupValues?.get(1)
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'operation' required: distance, bearing, or polygon_area"}""")

                when (op) {
                    "distance" -> {
                        val lat1 = extractDouble(args, "lat1") ?: return@ToolDefinition ToolResult.Text("""{"error":"lat1 required"}""")
                        val lon1 = extractDouble(args, "lon1") ?: return@ToolDefinition ToolResult.Text("""{"error":"lon1 required"}""")
                        val lat2 = extractDouble(args, "lat2") ?: return@ToolDefinition ToolResult.Text("""{"error":"lat2 required"}""")
                        val lon2 = extractDouble(args, "lon2") ?: return@ToolDefinition ToolResult.Text("""{"error":"lon2 required"}""")
                        val km   = haversineKm(lat1, lon1, lat2, lon2)
                        ToolResult.Text("""{"distance_km":${"%.3f".format(km)},"distance_miles":${"%.3f".format(km * 0.621371)},"distance_m":${"%.1f".format(km * 1000)}}""")
                    }
                    "bearing" -> {
                        val lat1 = extractDouble(args, "lat1") ?: return@ToolDefinition ToolResult.Text("""{"error":"lat1 required"}""")
                        val lon1 = extractDouble(args, "lon1") ?: return@ToolDefinition ToolResult.Text("""{"error":"lon1 required"}""")
                        val lat2 = extractDouble(args, "lat2") ?: return@ToolDefinition ToolResult.Text("""{"error":"lat2 required"}""")
                        val lon2 = extractDouble(args, "lon2") ?: return@ToolDefinition ToolResult.Text("""{"error":"lon2 required"}""")
                        val bearing = bearingDeg(lat1, lon1, lat2, lon2)
                        ToolResult.Text("""{"bearing_deg":${"%.1f".format(bearing)},"compass":"${compassPoint(bearing)}"}""")
                    }
                    "polygon_area" -> {
                        val points = parseLatLonArray(args)
                            ?: return@ToolDefinition ToolResult.Text("""{"error":"'points' must be an array of {\"lat\":...,\"lon\":...}"}""")
                        if (points.size < 3) return@ToolDefinition ToolResult.Text("""{"error":"polygon needs at least 3 points"}""")
                        val areaM2 = polygonAreaM2(points)
                        ToolResult.Text("""{"area_m2":${"%.1f".format(areaM2)},"area_km2":${"%.4f".format(areaM2 / 1e6)},"area_acres":${"%.2f".format(areaM2 / 4046.856)},"area_hectares":${"%.4f".format(areaM2 / 10000)}}""")
                    }
                    else -> ToolResult.Text("""{"error":"Unknown operation '$op'. Use: distance, bearing, polygon_area"}""")
                }
            }
        ))
    }

    // ── Geometry math ─────────────────────────────────────────────────────────

    private fun haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R  = 6371.0
        val dLat = (lat2 - lat1).toRad()
        val dLon = (lon2 - lon1).toRad()
        val a  = sin(dLat / 2).pow(2) + cos(lat1.toRad()) * cos(lat2.toRad()) * sin(dLon / 2).pow(2)
        return 2 * R * asin(sqrt(a))
    }

    private fun bearingDeg(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLon = (lon2 - lon1).toRad()
        val y    = sin(dLon) * cos(lat2.toRad())
        val x    = cos(lat1.toRad()) * sin(lat2.toRad()) - sin(lat1.toRad()) * cos(lat2.toRad()) * cos(dLon)
        return ((atan2(y, x).toDeg() + 360) % 360)
    }

    private fun compassPoint(deg: Double): String {
        val dirs = listOf("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW")
        return dirs[((deg + 11.25) / 22.5).toInt() % 16]
    }

    /** Spherical excess formula for polygon area on Earth's surface (m²). */
    private fun polygonAreaM2(points: List<Pair<Double, Double>>): Double {
        val R  = 6371000.0
        var area = 0.0
        val n = points.size
        for (i in 0 until n) {
            val (lat1, lon1) = points[i]
            val (lat2, lon2) = points[(i + 1) % n]
            area += (lon2 - lon1).toRad() * (2 + sin(lat1.toRad()) + sin(lat2.toRad()))
        }
        return abs(area * R * R / 2)
    }

    // ── Parsing helpers ───────────────────────────────────────────────────────

    private fun parseDoubleArray(args: String, key: String): List<Double>? {
        val match = Regex("\"$key\"\\s*:\\s*\\[([^]]+)]").find(args) ?: return null
        return match.groupValues[1].split(",").mapNotNull { it.trim().toDoubleOrNull() }
            .takeIf { it.isNotEmpty() }
    }

    private fun parseLatLonArray(args: String): List<Pair<Double, Double>>? {
        val arrayMatch = Regex("\"points\"\\s*:\\s*\\[(.+)]", RegexOption.DOT_MATCHES_ALL).find(args)
            ?: return null
        val pointRe = Regex("\\{[^}]*\"lat\"\\s*:\\s*(-?[0-9.]+)[^}]*\"lon\"\\s*:\\s*(-?[0-9.]+)[^}]*}")
        return pointRe.findAll(arrayMatch.groupValues[1]).map {
            it.groupValues[1].toDouble() to it.groupValues[2].toDouble()
        }.toList().takeIf { it.isNotEmpty() }
    }

    private fun extractDouble(args: String, key: String): Double? =
        Regex("\"$key\"\\s*:\\s*(-?[0-9.]+)").find(args)?.groupValues?.get(1)?.toDoubleOrNull()

    private fun extractInt(args: String, key: String): Int? =
        Regex("\"$key\"\\s*:\\s*([0-9]+)").find(args)?.groupValues?.get(1)?.toIntOrNull()

    private fun nextPowerOfTwo(n: Int): Int {
        var p = 1
        while (p < n) p = p shl 1
        return p
    }

    private fun polyEquation(coeffs: DoubleArray): String {
        return coeffs.mapIndexed { i, c ->
            when (i) {
                0    -> "%.4f".format(c)
                1    -> " + %.4fx".format(c)
                else -> " + %.4fx^$i".format(c)
            }
        }.joinToString("")
    }

    private fun Double.toRad() = this * PI / 180.0
    private fun Double.toDeg() = this * 180.0 / PI
}
