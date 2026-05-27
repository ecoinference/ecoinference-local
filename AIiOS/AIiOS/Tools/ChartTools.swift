import UIKit

/// On-device chart rendering tools using UIKit / Core Graphics.
/// No external charting library — themed to EcoInference brand colours.
/// Mirrors Android ChartTools.kt.
///
/// Tools:
///   plot_line    — line chart with optional labels
///   plot_bar     — bar chart with category labels
///   plot_scatter — scatter plot from x/y arrays
///
/// All return ToolResult.image (UIImage PNG + text caption).
enum ChartTools {

    // MARK: - Canvas constants

    private static let W: CGFloat = 800
    private static let H: CGFloat = 500
    private static let ML: CGFloat = 80   // margin left  (Y-axis labels)
    private static let MT: CGFloat = 65   // margin top   (title)
    private static let MR: CGFloat = 30   // margin right
    private static let MB: CGFloat = 75   // margin bottom (X-axis labels)

    private static var CL: CGFloat { ML }
    private static var CT: CGFloat { MT }
    private static var CR: CGFloat { W - MR }
    private static var CB: CGFloat { H - MB }
    private static var CW: CGFloat { CR - CL }
    private static var CH: CGFloat { CB - CT }

    // MARK: - EcoInference brand colours

    private static let cBg         = UIColor(red:0.059, green:0.141, blue:0.082, alpha:1)  // #0F2415 CardDark
    private static let cGreen      = UIColor(red:0.133, green:0.773, blue:0.369, alpha:1)  // #22C55E Green
    private static let cDimGreen   = UIColor(red:0.290, green:0.871, blue:0.502, alpha:1)  // #4ADE80 DimGreen
    private static let cNearWhite  = UIColor(red:0.941, green:0.992, blue:0.957, alpha:1)  // #F0FDF4 NearWhite
    private static let cGrid       = UIColor(red:0.102, green:0.227, blue:0.133, alpha:1)  // #1A3A22 CardBorder
    private static let cTeal       = UIColor(red:0.078, green:0.722, blue:0.651, alpha:1)  // #14B8A6 Teal

    // MARK: - Registration

    static func register() {
        registerPlotLine()
        registerPlotBar()
        registerPlotScatter()
    }

    // MARK: - plot_line

    private static func registerPlotLine() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "plot_line",
            description:   "Renders a line chart from a values array and optional X-axis labels. Returns an inline chart image.",
            parametersDoc: "title: string (optional), labels: array of strings (optional), values: array of numbers, x_label: string (optional), y_label: string (optional)",
            argsExample:   "{\"title\":\"Monthly Sales\",\"labels\":[\"Jan\",\"Feb\",\"Mar\"],\"values\":[100,150,120],\"y_label\":\"Units\"}",
            execute: { args in
                guard let values = args.toolDoubleArray("values"), !values.isEmpty else {
                    return .text(#"{"error":"'values' required"}"#)
                }
                let rawLabels = args.toolStringArray("labels")
                let labels    = alignLabels(rawLabels, values.count)
                let title     = args.toolStr("title")   ?? ""
                let xLabel    = args.toolStr("x_label") ?? ""
                let yLabel    = args.toolStr("y_label") ?? ""
                let image     = drawLineChart(title: title, labels: labels, values: values,
                                              xLabel: xLabel, yLabel: yLabel)
                let caption   = buildCaption("line chart", title: title, values: values)
                return .image(image, caption: caption)
            }
        ))
    }

    // MARK: - plot_bar

    private static func registerPlotBar() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "plot_bar",
            description:   "Renders a bar chart from category labels and values. Returns an inline chart image.",
            parametersDoc: "title: string (optional), labels: array of strings, values: array of numbers, x_label: string (optional), y_label: string (optional)",
            argsExample:   "{\"title\":\"Category Breakdown\",\"labels\":[\"A\",\"B\",\"C\"],\"values\":[45,30,25],\"y_label\":\"Count\"}",
            execute: { args in
                guard let labels = args.toolStringArray("labels") else {
                    return .text(#"{"error":"'labels' required"}"#)
                }
                guard let values = args.toolDoubleArray("values") else {
                    return .text(#"{"error":"'values' required"}"#)
                }
                guard labels.count == values.count else {
                    return .text(#"{"error":"labels and values must have the same length"}"#)
                }
                let title  = args.toolStr("title")   ?? ""
                let xLabel = args.toolStr("x_label") ?? ""
                let yLabel = args.toolStr("y_label") ?? ""
                let image  = drawBarChart(title: title, labels: labels, values: values,
                                          xLabel: xLabel, yLabel: yLabel)
                let caption = buildCaption("bar chart", title: title, values: values)
                return .image(image, caption: caption)
            }
        ))
    }

    // MARK: - plot_scatter

    private static func registerPlotScatter() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "plot_scatter",
            description:   "Renders a scatter plot from x and y value arrays. Returns an inline chart image.",
            parametersDoc: "title: string (optional), x: array of numbers, y: array of numbers, x_label: string (optional), y_label: string (optional)",
            argsExample:   "{\"title\":\"Correlation\",\"x\":[1,2,3,4,5],\"y\":[2.1,3.8,6.2,7.9,10.1],\"x_label\":\"X\",\"y_label\":\"Y\"}",
            execute: { args in
                guard let xVals = args.toolDoubleArray("x") else {
                    return .text(#"{"error":"'x' required"}"#)
                }
                guard let yVals = args.toolDoubleArray("y") else {
                    return .text(#"{"error":"'y' required"}"#)
                }
                guard xVals.count == yVals.count, !xVals.isEmpty else {
                    return .text(#"{"error":"x and y must be non-empty arrays of equal length"}"#)
                }
                let title  = args.toolStr("title")   ?? ""
                let xLabel = args.toolStr("x_label") ?? ""
                let yLabel = args.toolStr("y_label") ?? ""
                let image  = drawScatterChart(title: title, xVals: xVals, yVals: yVals,
                                              xLabel: xLabel, yLabel: yLabel)
                let cap = (title.isEmpty ? "" : "\(title) — ") + "Scatter plot of \(xVals.count) points"
                return .image(image, caption: cap)
            }
        ))
    }

    // MARK: - Drawing: line chart

    private static func drawLineChart(title: String, labels: [String], values: [Double],
                                       xLabel: String, yLabel: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
        return renderer.image { _ in
            cBg.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))

            let (yMin, yMax, yGrid) = niceRange(values.min()!, values.max()!)
            drawScaffold(title: title, xLabel: xLabel, yLabel: yLabel,
                         xLabels: labels, yMin: yMin, yMax: yMax, yGrid: yGrid)

            let n = values.count
            // Line
            if n > 1 {
                let path = UIBezierPath()
                for (i, v) in values.enumerated() {
                    let x = CL + CGFloat(i) / CGFloat(n - 1) * CW
                    let y = mapY(v, yMin: yMin, yMax: yMax)
                    i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                cGreen.setStroke()
                path.lineWidth = 3
                path.stroke()
            }
            // Dots
            for (i, v) in values.enumerated() {
                let x = CL + (n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0.5) * CW
                let y = mapY(v, yMin: yMin, yMax: yMax)
                cGreen.setFill()
                UIBezierPath(ovalIn: CGRect(x: x-6, y: y-6, width: 12, height: 12)).fill()
                cBg.setFill()
                UIBezierPath(ovalIn: CGRect(x: x-3, y: y-3, width: 6, height: 6)).fill()
            }
        }
    }

    // MARK: - Drawing: bar chart

    private static func drawBarChart(title: String, labels: [String], values: [Double],
                                      xLabel: String, yLabel: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
        return renderer.image { _ in
            cBg.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))

            let (yMin, yMax, yGrid) = niceRange(min(0, values.min()!), max(0, values.max()!))
            drawScaffold(title: title, xLabel: xLabel, yLabel: yLabel,
                         xLabels: labels, yMin: yMin, yMax: yMax, yGrid: yGrid)

            let zeroY = mapY(0, yMin: yMin, yMax: yMax)
            let n     = values.count
            let slotW = CW / CGFloat(n)
            let barW  = slotW * 0.65

            for (i, v) in values.enumerated() {
                let barX = CL + CGFloat(i) * slotW + (slotW - barW) / 2
                let barY = mapY(v, yMin: yMin, yMax: yMax)
                let rect: CGRect = v >= 0
                    ? CGRect(x: barX, y: barY, width: barW, height: zeroY - barY)
                    : CGRect(x: barX, y: zeroY, width: barW, height: barY - zeroY)
                cGreen.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
            }
        }
    }

    // MARK: - Drawing: scatter chart

    private static func drawScatterChart(title: String, xVals: [Double], yVals: [Double],
                                          xLabel: String, yLabel: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
        return renderer.image { _ in
            cBg.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))

            let (yMin, yMax, yGrid)  = niceRange(yVals.min()!, yVals.max()!)
            let (xMin, xMax, xGrid)  = niceRange(xVals.min()!, xVals.max()!)
            let xLabels = (0...xGrid).map { k -> String in
                fmtAxisVal(xMin + (xMax - xMin) * Double(k) / Double(xGrid))
            }
            drawScaffold(title: title, xLabel: xLabel, yLabel: yLabel,
                         xLabels: xLabels, yMin: yMin, yMax: yMax, yGrid: yGrid)

            for (x, y) in zip(xVals, yVals) {
                let px = CL + CGFloat((x - xMin) / (xMax - xMin)) * CW
                let py = mapY(y, yMin: yMin, yMax: yMax)
                cGreen.setFill()
                UIBezierPath(ovalIn: CGRect(x: px-7, y: py-7, width: 14, height: 14)).fill()
                cTeal.setFill()
                UIBezierPath(ovalIn: CGRect(x: px-4, y: py-4, width: 8, height: 8)).fill()
            }
        }
    }

    // MARK: - Shared scaffold (axes, grid, labels)

    private static func drawScaffold(title: String, xLabel: String, yLabel: String,
                                      xLabels: [String], yMin: Double, yMax: Double, yGrid: Int) {
        // Title
        if !title.isEmpty {
            drawText(title, in: CGRect(x: 0, y: 12, width: W, height: 34),
                     size: 24, color: cNearWhite, align: .center, bold: true)
        }
        // Horizontal grid + Y labels
        for i in 0...yGrid {
            let frac = CGFloat(i) / CGFloat(yGrid)
            let y    = CB - frac * CH
            let v    = yMin + (yMax - yMin) * Double(i) / Double(yGrid)
            cGrid.setStroke()
            let line = UIBezierPath(); line.move(to: CGPoint(x: CL, y: y))
            line.addLine(to: CGPoint(x: CR, y: y)); line.lineWidth = 1; line.stroke()
            drawText(fmtAxisVal(v), in: CGRect(x: 0, y: y - 8, width: CL - 6, height: 16),
                     size: 11, color: cDimGreen, align: .right)
        }
        // Axes
        cDimGreen.setStroke()
        let axes = UIBezierPath()
        axes.move(to: CGPoint(x: CL, y: CT)); axes.addLine(to: CGPoint(x: CL, y: CB))  // Y
        axes.move(to: CGPoint(x: CL, y: CB)); axes.addLine(to: CGPoint(x: CR, y: CB))  // X
        axes.lineWidth = 2; axes.stroke()
        // Zero line if range crosses zero
        if yMin < 0 && yMax > 0 {
            let zy = mapY(0, yMin: yMin, yMax: yMax)
            let zl = UIBezierPath()
            zl.move(to: CGPoint(x: CL, y: zy)); zl.addLine(to: CGPoint(x: CR, y: zy))
            zl.lineWidth = 1.5; cDimGreen.withAlphaComponent(0.5).setStroke(); zl.stroke()
        }
        // X labels
        let nX = max(xLabels.count - 1, 1)
        for (i, label) in xLabels.enumerated() {
            let x = CL + CGFloat(i) / CGFloat(nX) * CW
            drawText(String(label.prefix(9)),
                     in: CGRect(x: x - 30, y: CB + 6, width: 60, height: 16),
                     size: 11, color: cDimGreen, align: .center)
        }
        // Axis name labels
        if !xLabel.isEmpty {
            drawText(xLabel, in: CGRect(x: 0, y: H - 20, width: W, height: 18),
                     size: 14, color: cNearWhite, align: .center)
        }
        if !yLabel.isEmpty {
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.saveGState()
            ctx.translateBy(x: 18, y: (CT + CB) / 2)
            ctx.rotate(by: -.pi / 2)
            drawText(yLabel, in: CGRect(x: -60, y: -10, width: 120, height: 20),
                     size: 14, color: cNearWhite, align: .center)
            ctx.restoreGState()
        }
    }

    // MARK: - Utilities

    private static func mapY(_ v: Double, yMin: Double, yMax: Double) -> CGFloat {
        CB - CGFloat((v - yMin) / (yMax - yMin)) * CH
    }

    private static func drawText(_ text: String, in rect: CGRect,
                                   size: CGFloat, color: UIColor,
                                   align: NSTextAlignment = .left, bold: Bool = false) {
        let para = NSMutableParagraphStyle(); para.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular),
            .foregroundColor: color,
            .paragraphStyle:  para,
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func buildCaption(_ type: String, title: String, values: [Double]) -> String {
        let t = title.isEmpty ? "" : "\(title) — "
        return "\(t)\(type.prefix(1).uppercased() + type.dropFirst()) of \(values.count) data points (min=\(fmtAxisVal(values.min()!)), max=\(fmtAxisVal(values.max()!)))"
    }

    private static func niceRange(_ minV: Double, _ maxV: Double) -> (Double, Double, Int) {
        if minV == maxV { return (minV - 1, maxV + 1, 4) }
        let range = maxV - minV
        let step  = niceNum(range / 4, round: true)
        let nMin  = floor(minV / step) * step
        let nMax  = ceil(maxV  / step) * step
        let count = max(2, min(8, Int(((nMax - nMin) / step).rounded())))
        return (nMin, nMax, count)
    }

    private static func niceNum(_ v: Double, round: Bool) -> Double {
        let exp = floor(log10(v))
        let f   = v / pow(10, exp)
        let nf: Double
        if round { nf = f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10 }
        else      { nf = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10 }
        return nf * pow(10, exp)
    }

    private static func fmtAxisVal(_ v: Double) -> String {
        let a = abs(v)
        if a == 0      { return "0" }
        if a >= 1000   { return String(format: "%.0f", v) }
        if a >= 100    { return String(format: "%.0f", v) }
        if a >= 10     { return String(format: "%.1f", v) }
        if a >= 1      { return String(format: "%.2f", v) }
        return String(format: "%.3f", v)
    }

    private static func alignLabels(_ labels: [String]?, _ size: Int) -> [String] {
        guard let labels else { return (1...size).map { "\($0)" } }
        return (0..<size).map { i in labels.indices.contains(i) ? labels[i] : "\(i+1)" }
    }
}

