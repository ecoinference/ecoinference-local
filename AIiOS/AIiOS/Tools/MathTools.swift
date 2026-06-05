import Foundation

/// On-device math and signal processing tools.
/// No network calls, fully offline. Mirrors Android MathTools.kt.
///
/// Tools:
///   compute_stats    — descriptive statistics
///   run_fft          — Fast Fourier Transform (Cooley-Tukey)
///   fit_curve        — polynomial regression (R²)
///   compute_geometry — Haversine distance, bearing, polygon area
enum MathTools {

    static func register() {
        registerStats()
        registerFft()
        registerFitCurve()
        registerGeometry()
    }

    // MARK: - Descriptive statistics

    private static func registerStats() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "compute_stats",
            description:   "Computes descriptive statistics for a list of numbers: mean, median, std dev, min, max, percentiles.",
            parametersDoc: "data: array of numbers",
            argsExample:   "{\"data\":[1,2,3,4,5,6,7,8,9,10]}",
            execute: { args in
                guard let data = args.toolDoubleArray("data"), !data.isEmpty else {
                    return .text(#"{"error":"'data' must be a non-empty array of numbers"}"#)
                }
                let sorted   = data.sorted()
                let n        = Double(data.count)
                let mean     = data.reduce(0, +) / n
                let median   = percentile(sorted, 50)
                let variance = data.map { pow($0 - mean, 2) }.reduce(0, +) / max(n - 1, 1)
                let stdDev   = variance.squareRoot()
                return .text("""
{"count":\(data.count),"mean":\(fmt4(mean)),"median":\(fmt4(median)),"std_dev":\(fmt4(stdDev)),"variance":\(fmt4(variance)),"min":\(sorted.first!),"max":\(sorted.last!),"p25":\(fmt4(percentile(sorted,25))),"p75":\(fmt4(percentile(sorted,75))),"p90":\(fmt4(percentile(sorted,90)))}
""".trimmingCharacters(in: .newlines))
            }
        ))
    }

    // MARK: - FFT

    private static func registerFft() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "run_fft",
            description:   "Runs a Fast Fourier Transform on a data array. Returns dominant frequency components and magnitudes.",
            parametersDoc: "data: array of numbers, sample_rate_hz: number (optional, default 1.0), top_n: number (optional, default 5)",
            argsExample:   "{\"data\":[0,1,0,-1,0,1,0,-1],\"sample_rate_hz\":8.0,\"top_n\":3}",
            execute: { args in
                guard let data = args.toolDoubleArray("data"), data.count >= 2 else {
                    return .text(#"{"error":"'data' must be an array of at least 2 numbers"}"#)
                }
                let sampleRate = args.toolDouble("sample_rate_hz") ?? 1.0
                let topN       = args.toolInt("top_n") ?? 5
                let n          = nextPow2(data.count)
                var real       = data + Array(repeating: 0.0, count: n - data.count)
                var imag       = Array(repeating: 0.0, count: n)
                fft(real: &real, imag: &imag)
                let half = n / 2
                let bins = (1..<half).map { k -> (freq: Double, mag: Double) in
                    let mag  = (real[k]*real[k] + imag[k]*imag[k]).squareRoot() / Double(n)
                    let freq = Double(k) * sampleRate / Double(n)
                    return (freq, mag)
                }.sorted { $0.mag > $1.mag }.prefix(topN)
                let binsJson = bins.map { "{\"freq_hz\":\(fmt4($0.freq)),\"magnitude\":\(fmt4($0.mag))}" }
                    .joined(separator: ",")
                return .text("""
{"n_samples":\(data.count),"n_padded":\(n),"sample_rate_hz":\(sampleRate),"top_frequencies":[\(binsJson)]}
""".trimmingCharacters(in: .newlines))
            }
        ))
    }

    // MARK: - Curve fitting

    private static func registerFitCurve() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "fit_curve",
            description:   "Fits a polynomial curve to x,y data. Returns coefficients and R² goodness-of-fit.",
            parametersDoc: "x: array of numbers, y: array of numbers, degree: number (1=linear, 2=quadratic, 3=cubic; default 1)",
            argsExample:   "{\"x\":[1,2,3,4,5],\"y\":[2.1,3.9,6.2,7.8,10.1],\"degree\":1}",
            execute: { args in
                guard let x = args.toolDoubleArray("x") else { return .text(#"{"error":"'x' required"}"#) }
                guard let y = args.toolDoubleArray("y") else { return .text(#"{"error":"'y' required"}"#) }
                guard x.count == y.count else { return .text(#"{"error":"x and y must have the same length"}"#) }
                let degree = args.toolInt("degree") ?? 1
                guard degree >= 1 && degree <= 5 else { return .text(#"{"error":"degree must be 1–5"}"#) }
                guard x.count >= degree + 1 else { return .text(#"{"error":"need at least degree+1 data points"}"#) }

                guard let coeffs = fitPolynomial(x: x, y: y, degree: degree) else {
                    return .text(#"{"error":"Matrix is singular — cannot fit curve"}"#)
                }

                // R²
                let yMean  = y.reduce(0, +) / Double(y.count)
                let ssTot  = y.map { pow($0 - yMean, 2) }.reduce(0, +)
                let ssRes  = zip(x, y).map { (xi, yi) in pow(yi - polyEval(coeffs, xi), 2) }.reduce(0, +)
                let r2     = ssTot == 0 ? 1.0 : 1.0 - ssRes / ssTot

                let label  = ["","linear","quadratic","cubic","degree-4","degree-5"][degree]
                let coeffJson = coeffs.enumerated().map { "\"c\($0.offset)\":\(String(format:"%.6f",$0.element))" }
                    .joined(separator: ",")
                return .text("""
{"degree":\(degree),"type":"\(label)","coefficients":{\(coeffJson)},"r_squared":\(fmt4(r2)),"equation":"\(polyEquation(coeffs))"}
""".trimmingCharacters(in: .newlines))
            }
        ))
    }

    // MARK: - Geometry

    private static func registerGeometry() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "compute_geometry",
            description:   "Computes GPS distance (Haversine), bearing, or polygon area.",
            parametersDoc: "operation: \"distance\"|\"bearing\"|\"polygon_area\". distance/bearing: lat1,lon1,lat2,lon2. polygon_area: points:[{lat,lon}]",
            argsExample:   "{\"operation\":\"distance\",\"lat1\":37.7749,\"lon1\":-122.4194,\"lat2\":34.0522,\"lon2\":-118.2437}",
            execute: { args in
                guard let op = args["operation"] as? String else {
                    return .text(#"{"error":"'operation' required: distance, bearing, polygon_area"}"#)
                }
                switch op {
                case "distance":
                    guard let lat1 = args.toolDouble("lat1"), let lon1 = args.toolDouble("lon1"),
                          let lat2 = args.toolDouble("lat2"), let lon2 = args.toolDouble("lon2") else {
                        return .text(#"{"error":"lat1,lon1,lat2,lon2 required"}"#)
                    }
                    let km = haversineKm(lat1, lon1, lat2, lon2)
                    return .text("""
{"distance_km":\(String(format:"%.3f",km)),"distance_miles":\(String(format:"%.3f",km*0.621371)),"distance_m":\(String(format:"%.1f",km*1000))}
""".trimmingCharacters(in: .newlines))

                case "bearing":
                    guard let lat1 = args.toolDouble("lat1"), let lon1 = args.toolDouble("lon1"),
                          let lat2 = args.toolDouble("lat2"), let lon2 = args.toolDouble("lon2") else {
                        return .text(#"{"error":"lat1,lon1,lat2,lon2 required"}"#)
                    }
                    let b = bearingDeg(lat1, lon1, lat2, lon2)
                    return .text("""
{"bearing_deg":\(String(format:"%.1f",b)),"compass":"\(compassPoint(b))"}
""".trimmingCharacters(in: .newlines))

                case "polygon_area":
                    guard let pts = args["points"] as? [[String: Any]] else {
                        return .text(#"{"error":"'points' must be an array of {lat,lon} objects"}"#)
                    }
                    let coords = pts.compactMap { p -> (Double, Double)? in
                        guard let lat = (p["lat"] as? Double) ?? (p["lat"] as? Int).map(Double.init),
                              let lon = (p["lon"] as? Double) ?? (p["lon"] as? Int).map(Double.init)
                        else { return nil }
                        return (lat, lon)
                    }
                    guard coords.count >= 3 else { return .text(#"{"error":"polygon needs at least 3 points"}"#) }
                    let aM2 = polygonAreaM2(coords)
                    return .text("""
{"area_m2":\(String(format:"%.1f",aM2)),"area_km2":\(String(format:"%.4f",aM2/1e6)),"area_acres":\(String(format:"%.2f",aM2/4046.856)),"area_hectares":\(String(format:"%.4f",aM2/10000))}
""".trimmingCharacters(in: .newlines))

                default:
                    return .text(#"{"error":"Unknown operation. Use: distance, bearing, polygon_area"}"#)
                }
            }
        ))
    }

    // MARK: - FFT (Cooley-Tukey iterative)

    private static func fft(real: inout [Double], imag: inout [Double]) {
        let n = real.count
        guard n > 1 else { return }
        // Bit-reversal permutation
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { real.swapAt(i, j); imag.swapAt(i, j) }
        }
        // Butterfly
        var len = 2
        while len <= n {
            let half = len / 2
            let ang  = -2.0 * .pi / Double(len)
            let wR = cos(ang), wI = sin(ang)
            var k = 0
            while k < n {
                var tR = 1.0, tI = 0.0
                for m in 0..<half {
                    let uR = real[k+m], uI = imag[k+m]
                    let vR = tR*real[k+m+half] - tI*imag[k+m+half]
                    let vI = tR*imag[k+m+half] + tI*real[k+m+half]
                    real[k+m] = uR+vR; imag[k+m] = uI+vI
                    real[k+m+half] = uR-vR; imag[k+m+half] = uI-vI
                    let newTR = tR*wR - tI*wI; tI = tR*wI + tI*wR; tR = newTR
                }
                k += len
            }
            len <<= 1
        }
    }

    // MARK: - Polynomial fitting (Gauss-Jordan)

    private static func fitPolynomial(x: [Double], y: [Double], degree: Int) -> [Double]? {
        let d = degree + 1
        // Build normal equations: A*c = b
        var A = [[Double]](repeating: [Double](repeating: 0, count: d), count: d)
        var b = [Double](repeating: 0, count: d)
        for k in 0..<x.count {
            var xpow = [Double](repeating: 1.0, count: 2 * degree + 1)
            for i in 1..<xpow.count { xpow[i] = xpow[i-1] * x[k] }
            for i in 0..<d {
                b[i] += xpow[i] * y[k]
                for j in 0..<d { A[i][j] += xpow[i+j] }
            }
        }
        // Augmented [A|b]
        var aug = (0..<d).map { i in A[i] + [b[i]] }
        for col in 0..<d {
            var maxRow = col
            for row in (col+1)..<d { if abs(aug[row][col]) > abs(aug[maxRow][col]) { maxRow = row } }
            aug.swapAt(col, maxRow)
            guard abs(aug[col][col]) > 1e-12 else { return nil }
            let pivot = aug[col][col]
            for j in 0...d { aug[col][j] /= pivot }
            for row in 0..<d where row != col {
                let f = aug[row][col]
                for j in 0...d { aug[row][j] -= f * aug[col][j] }
            }
        }
        return (0..<d).map { aug[$0][d] }
    }

    private static func polyEval(_ coeffs: [Double], _ x: Double) -> Double {
        coeffs.enumerated().map { pow(x, Double($0.offset)) * $0.element }.reduce(0, +)
    }

    private static func polyEquation(_ coeffs: [Double]) -> String {
        coeffs.enumerated().map { (i, c) in
            switch i {
            case 0: return String(format: "%.4f", c)
            case 1: return String(format: " + %.4fx", c)
            default: return String(format: " + %.4fx^%d", c, i)
            }
        }.joined()
    }

    // MARK: - Geometry math

    private static func haversineKm(_ lat1: Double, _ lon1: Double,
                                     _ lat2: Double, _ lon2: Double) -> Double {
        let R    = 6371.0
        let rad  = Double.pi / 180
        let dLat = (lat2 - lat1) * rad
        let dLon = (lon2 - lon1) * rad
        let sinHalfLat = sin(dLat / 2)
        let sinHalfLon = sin(dLon / 2)
        let a = sinHalfLat * sinHalfLat
              + cos(lat1 * rad) * cos(lat2 * rad) * sinHalfLon * sinHalfLon
        return 2 * R * asin(a.squareRoot())
    }

    private static func bearingDeg(_ lat1: Double, _ lon1: Double,
                                    _ lat2: Double, _ lon2: Double) -> Double {
        let rad  = Double.pi / 180
        let dLon = (lon2 - lon1) * rad
        let y    = sin(dLon) * cos(lat2 * rad)
        let x    = cos(lat1 * rad) * sin(lat2 * rad)
                 - sin(lat1 * rad) * cos(lat2 * rad) * cos(dLon)
        return ((atan2(y, x) * 180 / Double.pi) + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func compassPoint(_ deg: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return dirs[Int((deg + 11.25) / 22.5) % 16]
    }

    private static func polygonAreaM2(_ pts: [(Double, Double)]) -> Double {
        let R = 6371000.0; var area = 0.0; let n = pts.count
        for i in 0..<n {
            let (lat1, lon1) = pts[i]; let (lat2, lon2) = pts[(i+1) % n]
            area += (lon2 - lon1) * .pi / 180 * (2 + sin(lat1 * .pi / 180) + sin(lat2 * .pi / 180))
        }
        return abs(area * R * R / 2)
    }

    // MARK: - Helpers

    private static func nextPow2(_ n: Int) -> Int { var p = 1; while p < n { p <<= 1 }; return p }
    private static func fmt4(_ v: Double) -> String { String(format: "%.4f", v) }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let idx   = (p / 100.0) * Double(sorted.count - 1)
        let lower = Int(idx)
        let frac  = idx - Double(lower)
        if lower >= sorted.count - 1 { return sorted.last! }
        return sorted[lower] + frac * (sorted[lower + 1] - sorted[lower])
    }
}

// MARK: - Dictionary helpers (internal — shared with AstralTools, HardwareTools, ChartTools)

extension Dictionary where Key == String, Value == Any {
    func toolDouble(_ key: String) -> Double? {
        if let v = self[key] as? Double { return v }
        if let v = self[key] as? Int    { return Double(v) }
        return nil
    }
    func toolInt(_ key: String) -> Int? {
        if let v = self[key] as? Int    { return v }
        if let v = self[key] as? Double { return Int(v) }
        return nil
    }
    func toolDoubleArray(_ key: String) -> [Double]? {
        // JSONSerialization on iOS produces NSNumber — cast via .doubleValue to be safe.
        // Also handle [String] in case the model quotes the numbers.
        let raw = self[key]
        print("[toolDoubleArray] key=\(key) raw type=\(type(of: raw)) value=\(String(describing: raw))")
        guard let arr = raw as? [Any] else { return nil }
        let result = arr.compactMap { v -> Double? in
            if let n = v as? NSNumber { return n.doubleValue }   // NSNumber from JSONSerialization
            if let d = v as? Double   { return d }
            if let i = v as? Int      { return Double(i) }
            if let s = v as? String   { return Double(s) }
            return nil
        }
        print("[toolDoubleArray] key=\(key) result=\(result)")
        return result.isEmpty ? nil : result
    }
    func toolStringArray(_ key: String) -> [String]? {
        // Accept a plain [String] or coerce a mixed array (model may send numbers as labels)
        if let arr = self[key] as? [String] { return arr }
        guard let arr = self[key] as? [Any] else { return nil }
        let result = arr.map { v -> String in
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.doubleValue == n.doubleValue.rounded()
                                         ? String(n.intValue) : String(n.doubleValue) }
            if let i = v as? Int    { return String(i) }
            if let d = v as? Double { return d == d.rounded() ? String(Int(d)) : String(d) }
            return String(describing: v)
        }
        return result.isEmpty ? nil : result
    }
    func toolStr(_ key: String) -> String? { self[key] as? String }
}
