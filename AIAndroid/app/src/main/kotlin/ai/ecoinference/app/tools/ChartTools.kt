package ai.ecoinference.app.tools

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/**
 * On-device chart rendering tools using Android Canvas.
 * No external charting library — themed to EcoInference brand colors.
 *
 * Tools:
 *   plot_line    — line chart with optional labels
 *   plot_bar     — bar chart with category labels
 *   plot_scatter — scatter plot from x/y arrays
 *
 * All return [ToolResult.Image] (PNG bytes + text caption).
 * The caption is what the model reads in <tool_result>; the PNG bytes are
 * forwarded to the UI via [AgentToken.ChartImage] for inline display.
 */
object ChartTools {

    // ── Canvas dimensions ──────────────────────────────────────────────────────
    private const val W  = 800
    private const val H  = 500
    private const val ML = 80f    // margin left   (Y-axis labels)
    private const val MT = 65f    // margin top    (title)
    private const val MR = 30f    // margin right
    private const val MB = 75f    // margin bottom (X-axis labels + name)

    // Chart area bounds (constant helpers)
    private val CL get() = ML
    private val CT get() = MT
    private val CR get() = W - MR
    private val CB get() = H - MB
    private val CW get() = CR - CL
    private val CH get() = CB - CT

    // ── EcoInference brand colors (Android ARGB ints) ────────────────────────
    private val C_BG         = 0xFF0F2415.toInt()   // EcoColors.CardDark
    private val C_GREEN      = 0xFF22C55E.toInt()   // EcoColors.Green
    private val C_DIM_GREEN  = 0xFF4ADE80.toInt()   // EcoColors.DimGreen
    private val C_NEAR_WHITE = 0xFFF0FDF4.toInt()   // EcoColors.NearWhite
    private val C_GRID       = 0xFF1A3A22.toInt()   // EcoColors.CardBorder
    private val C_TEAL       = 0xFF14B8A6.toInt()   // EcoColors.Teal  (dot fill)

    fun register() {
        registerPlotLine()
        registerPlotBar()
        registerPlotScatter()
    }

    // ── plot_line ─────────────────────────────────────────────────────────────

    private fun registerPlotLine() {
        ToolRegistry.register(ToolDefinition(
            name          = "plot_line",
            description   = "Renders a line chart from a values array and optional X-axis labels. Returns an inline chart image.",
            parametersDoc = "title: string (optional), labels: array of strings (optional), values: array of numbers, x_label: string (optional), y_label: string (optional)",
            argsExample   = """{"title":"Monthly Sales","labels":["Jan","Feb","Mar","Apr","May"],"values":[100,150,120,180,140],"y_label":"Units"}""",
            execute       = { args ->
                val values = parseDoubleArray(args, "values")
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'values' required"}""")
                if (values.isEmpty()) return@ToolDefinition ToolResult.Text("""{"error":"values array is empty"}""")
                val rawLabels = parseStringArray(args, "labels")
                val labels    = alignLabels(rawLabels, values.size)
                val title     = extractString(args, "title")   ?: ""
                val xLabel    = extractString(args, "x_label") ?: ""
                val yLabel    = extractString(args, "y_label") ?: ""
                val bytes     = drawLineChart(title, labels, values, xLabel, yLabel)
                val caption   = buildCaption("line chart", title, values)
                ToolResult.Image(bytes, caption)
            }
        ))
    }

    // ── plot_bar ──────────────────────────────────────────────────────────────

    private fun registerPlotBar() {
        ToolRegistry.register(ToolDefinition(
            name          = "plot_bar",
            description   = "Renders a bar chart from category labels and values. Returns an inline chart image.",
            parametersDoc = "title: string (optional), labels: array of strings, values: array of numbers, x_label: string (optional), y_label: string (optional)",
            argsExample   = """{"title":"Category Breakdown","labels":["A","B","C","D"],"values":[45,30,25,60],"y_label":"Count"}""",
            execute       = { args ->
                val rawLabels = parseStringArray(args, "labels")
                val rawValues = parseDoubleArray(args, "values")

                // 3-way recovery (mirrors iOS ChartTools):
                // 1. Both present → truncate to matching length (tolerates count mismatch)
                // 2. Values only  → auto-generate sequential index labels
                // 3. Numeric-string labels only → treat labels as values, use indices
                val (labels, values) = when {
                    rawLabels != null && rawValues != null -> {
                        val n = minOf(rawLabels.size, rawValues.size)
                        rawLabels.take(n) to rawValues.take(n)
                    }
                    rawValues != null -> {
                        rawValues.indices.map { "${it + 1}" } to rawValues
                    }
                    rawLabels != null && rawLabels.all { it.toDoubleOrNull() != null } -> {
                        val vals = rawLabels.mapNotNull { it.toDoubleOrNull() }
                        rawLabels.indices.map { "${it + 1}" } to vals
                    }
                    else -> return@ToolDefinition ToolResult.Text(
                        """{"error":"'values' required — provide actual numeric data, e.g. values:[10,20,30,40,50]"}"""
                    )
                }

                if (values.isEmpty()) return@ToolDefinition ToolResult.Text("""{"error":"values array is empty"}""")
                val title  = extractString(args, "title")   ?: ""
                val xLabel = extractString(args, "x_label") ?: ""
                val yLabel = extractString(args, "y_label") ?: ""
                val bytes  = drawBarChart(title, labels, values, xLabel, yLabel)
                val caption = buildCaption("bar chart", title, values)
                ToolResult.Image(bytes, caption)
            }
        ))
    }

    // ── plot_scatter ──────────────────────────────────────────────────────────

    private fun registerPlotScatter() {
        ToolRegistry.register(ToolDefinition(
            name          = "plot_scatter",
            description   = "Renders a scatter plot from x and y value arrays. Returns an inline chart image.",
            parametersDoc = "title: string (optional), x: array of numbers, y: array of numbers, x_label: string (optional), y_label: string (optional)",
            argsExample   = """{"title":"Correlation","x":[1,2,3,4,5],"y":[2.1,3.8,6.2,7.9,10.1],"x_label":"X","y_label":"Y"}""",
            execute       = { args ->
                val xVals = parseDoubleArray(args, "x")
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'x' required"}""")
                val yVals = parseDoubleArray(args, "y")
                    ?: return@ToolDefinition ToolResult.Text("""{"error":"'y' required"}""")
                if (xVals.size != yVals.size)
                    return@ToolDefinition ToolResult.Text("""{"error":"x and y must have the same length"}""")
                if (xVals.isEmpty())
                    return@ToolDefinition ToolResult.Text("""{"error":"x and y arrays are empty"}""")
                val title  = extractString(args, "title")   ?: ""
                val xLabel = extractString(args, "x_label") ?: ""
                val yLabel = extractString(args, "y_label") ?: ""
                val bytes  = drawScatterChart(title, xVals, yVals, xLabel, yLabel)
                val n      = xVals.size
                val cap    = "${if (title.isNotBlank()) "$title — " else ""}Scatter plot of $n points"
                ToolResult.Image(bytes, cap)
            }
        ))
    }

    // ── Drawing: line chart ───────────────────────────────────────────────────

    private fun drawLineChart(
        title: String, labels: List<String>, values: List<Double>,
        xLabel: String, yLabel: String,
    ): ByteArray {
        val bitmap = newBitmap()
        val canvas = Canvas(bitmap)
        val p      = newPaint()
        canvas.drawColor(C_BG)

        val (yMin, yMax, yGrid) = niceRange(values.min(), values.max())
        drawScaffold(canvas, p, yMin, yMax, yGrid, title, xLabel, yLabel, labels)

        val n = values.size

        // Line path
        if (n > 1) {
            p.color = C_GREEN; p.strokeWidth = 3f; p.style = Paint.Style.STROKE
            val path = Path()
            values.forEachIndexed { i, v ->
                val x = CL + i.toFloat() / (n - 1) * CW
                val y = mapY(v, yMin, yMax)
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            canvas.drawPath(path, p)
        }

        // Dots — green ring with dark fill
        values.forEachIndexed { i, v ->
            val x = CL + (if (n > 1) i.toFloat() / (n - 1) else 0.5f) * CW
            val y = mapY(v, yMin, yMax)
            p.style = Paint.Style.FILL; p.color = C_GREEN
            canvas.drawCircle(x, y, 6f, p)
            p.color = C_BG
            canvas.drawCircle(x, y, 3f, p)
        }

        return toPng(bitmap)
    }

    // ── Drawing: bar chart ────────────────────────────────────────────────────

    private fun drawBarChart(
        title: String, labels: List<String>, values: List<Double>,
        xLabel: String, yLabel: String,
    ): ByteArray {
        val bitmap = newBitmap()
        val canvas = Canvas(bitmap)
        val p      = newPaint()
        canvas.drawColor(C_BG)

        // Include 0 so bars always anchor to the zero line
        val (yMin, yMax, yGrid) = niceRange(minOf(0.0, values.min()), maxOf(0.0, values.max()))
        drawScaffold(canvas, p, yMin, yMax, yGrid, title, xLabel, yLabel, labels)

        val zeroY = mapY(0.0, yMin, yMax)
        val n     = values.size
        val slotW = CW / n
        val barW  = slotW * 0.65f

        values.forEachIndexed { i, v ->
            val barX  = CL + i * slotW + (slotW - barW) / 2f
            val barY  = mapY(v, yMin, yMax)
            p.style = Paint.Style.FILL
            p.color = C_GREEN
            if (v >= 0) canvas.drawRect(barX, barY, barX + barW, zeroY, p)
            else        canvas.drawRect(barX, zeroY, barX + barW, barY, p)
        }

        return toPng(bitmap)
    }

    // ── Drawing: scatter chart ────────────────────────────────────────────────

    private fun drawScatterChart(
        title: String, xVals: List<Double>, yVals: List<Double>,
        xLabel: String, yLabel: String,
    ): ByteArray {
        val bitmap = newBitmap()
        val canvas = Canvas(bitmap)
        val p      = newPaint()
        canvas.drawColor(C_BG)

        val (yMin, yMax, yGrid)  = niceRange(yVals.min(), yVals.max())
        val (xMin, xMax, xGrid)  = niceRange(xVals.min(), xVals.max())

        // Generate X-axis scale labels from the nice range
        val xLabels = (0..xGrid).map { k ->
            val v = xMin + (xMax - xMin) * k.toDouble() / xGrid
            fmtAxisVal(v)
        }

        drawScaffold(canvas, p, yMin, yMax, yGrid, title, xLabel, yLabel, xLabels)

        // Dots — teal fill, green ring
        xVals.zip(yVals).forEach { (x, y) ->
            val px = CL + ((x - xMin) / (xMax - xMin) * CW).toFloat()
            val py = mapY(y, yMin, yMax)
            p.style = Paint.Style.FILL
            p.color = C_GREEN
            canvas.drawCircle(px, py, 7f, p)
            p.color = C_TEAL
            canvas.drawCircle(px, py, 4f, p)
        }

        return toPng(bitmap)
    }

    // ── Shared scaffold (axes, grid, labels) ──────────────────────────────────

    private fun drawScaffold(
        canvas: Canvas, p: Paint,
        yMin: Double, yMax: Double, yGrid: Int,
        title: String, xLabel: String, yLabel: String,
        xLabels: List<String>,
    ) {
        // Title
        if (title.isNotBlank()) {
            p.style = Paint.Style.FILL
            p.color = C_NEAR_WHITE
            p.textSize = 24f
            p.textAlign = Paint.Align.CENTER
            p.typeface = Typeface.DEFAULT_BOLD
            canvas.drawText(title, W / 2f, 44f, p)
            p.typeface = Typeface.DEFAULT
        }

        // Horizontal grid lines + Y-axis value labels
        for (i in 0..yGrid) {
            val frac = i.toFloat() / yGrid
            val y    = CB - frac * CH
            val v    = yMin + (yMax - yMin) * i.toDouble() / yGrid

            p.color = C_GRID; p.strokeWidth = 1f; p.style = Paint.Style.STROKE
            canvas.drawLine(CL, y, CR, y, p)

            p.style = Paint.Style.FILL
            p.color = C_DIM_GREEN; p.textSize = 11f
            p.textAlign = Paint.Align.RIGHT
            canvas.drawText(fmtAxisVal(v), CL - 6f, y + 4f, p)
        }

        // Y axis + X axis
        p.color = C_DIM_GREEN; p.strokeWidth = 2f; p.style = Paint.Style.STROKE
        canvas.drawLine(CL, CT, CL, CB, p)
        canvas.drawLine(CL, CB, CR, CB, p)

        // Zero line (if range crosses zero and zero != bottom/top)
        if (yMin < 0 && yMax > 0) {
            val zy = mapY(0.0, yMin, yMax)
            p.color = C_DIM_GREEN.and(0x80FFFFFF.toInt()); p.strokeWidth = 1.5f
            canvas.drawLine(CL, zy, CR, zy, p)
        }

        // X-axis labels (evenly spaced across chart width)
        p.style = Paint.Style.FILL; p.color = C_DIM_GREEN; p.textSize = 11f
        p.textAlign = Paint.Align.CENTER
        val nX = (xLabels.size - 1).coerceAtLeast(1)
        xLabels.forEachIndexed { i, label ->
            val x = CL + i.toFloat() / nX * CW
            canvas.drawText(label.take(9), x, CB + 20f, p)
        }

        // Axis name labels
        p.style = Paint.Style.FILL; p.color = C_NEAR_WHITE; p.textSize = 14f
        p.textAlign = Paint.Align.CENTER
        if (xLabel.isNotBlank())
            canvas.drawText(xLabel, (CL + CR) / 2f, H - 12f, p)

        if (yLabel.isNotBlank()) {
            canvas.save()
            canvas.rotate(-90f, 18f, (CT + CB) / 2f)
            canvas.drawText(yLabel, 18f, (CT + CB) / 2f + 5f, p)
            canvas.restore()
        }
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    /** Map a data value to a canvas Y coordinate within the chart area. */
    private fun mapY(v: Double, yMin: Double, yMax: Double): Float =
        (CB - ((v - yMin) / (yMax - yMin) * CH)).toFloat()

    private fun newBitmap() = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)

    private fun newPaint() = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style    = Paint.Style.FILL
        typeface = Typeface.DEFAULT
    }

    private fun toPng(bitmap: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private fun buildCaption(type: String, title: String, values: List<Double>): String {
        val t = if (title.isNotBlank()) "$title — " else ""
        return "${t}${type.replaceFirstChar { it.uppercase() }} of ${values.size} data points " +
               "(min=${fmtAxisVal(values.min())}, max=${fmtAxisVal(values.max())})"
    }

    /**
     * Computes a "nice" axis range for [minV]..[maxV].
     * Returns (niceMin, niceMax, gridLineCount).
     */
    private fun niceRange(minV: Double, maxV: Double): Triple<Double, Double, Int> {
        if (minV == maxV) return Triple(minV - 1.0, maxV + 1.0, 4)
        val range = maxV - minV
        val step  = niceNum(range / 4.0, round = true)
        val nMin  = floor(minV / step) * step
        val nMax  = ceil(maxV  / step) * step
        val count = ((nMax - nMin) / step).toInt().coerceIn(2, 8)
        return Triple(nMin, nMax, count)
    }

    private fun niceNum(v: Double, round: Boolean): Double {
        val exp = floor(log10(v))
        val f   = v / 10.0.pow(exp)
        val nf  = if (round) {
            when { f < 1.5 -> 1.0; f < 3.0 -> 2.0; f < 7.0 -> 5.0; else -> 10.0 }
        } else {
            when { f <= 1.0 -> 1.0; f <= 2.0 -> 2.0; f <= 5.0 -> 5.0; else -> 10.0 }
        }
        return nf * 10.0.pow(exp)
    }

    private fun fmtAxisVal(v: Double): String = when {
        abs(v) == 0.0         -> "0"
        abs(v) >= 10_000      -> "%.0f".format(v)
        abs(v) >= 1_000       -> "%.0f".format(v)
        abs(v) >= 100         -> "%.0f".format(v)
        abs(v) >= 10          -> "%.1f".format(v)
        abs(v) >= 1           -> "%.2f".format(v)
        else                  -> "%.3f".format(v)
    }

    /** Ensure labels list has exactly [size] entries (pad with index strings). */
    private fun alignLabels(labels: List<String>?, size: Int): List<String> {
        if (labels == null) return (1..size).map { "$it" }
        if (labels.size == size) return labels
        // Truncate or pad
        return (0 until size).map { i -> labels.getOrElse(i) { "${i + 1}" } }
    }

    // ── Parsing helpers ───────────────────────────────────────────────────────

    private fun parseDoubleArray(args: String, key: String): List<Double>? {
        val match = Regex("\"$key\"\\s*:\\s*\\[([^]]+)]").find(args) ?: return null
        return match.groupValues[1].split(",")
            .mapNotNull { it.trim().toDoubleOrNull() }
            .takeIf { it.isNotEmpty() }
    }

    private fun parseStringArray(args: String, key: String): List<String>? {
        val match = Regex("\"$key\"\\s*:\\s*\\[([^]]*)]").find(args) ?: return null
        return Regex("\"([^\"]*)\"").findAll(match.groupValues[1])
            .map { it.groupValues[1] }
            .toList()
            .takeIf { it.isNotEmpty() }
    }

    private fun extractString(args: String, key: String): String? =
        Regex("\"$key\"\\s*:\\s*\"([^\"]*?)\"").find(args)?.groupValues?.get(1)
}
