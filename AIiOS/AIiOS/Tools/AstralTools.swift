import Foundation

/// On-device astronomical calculations — no network, no dependencies.
/// Mirrors Android AstralTools.kt (same algorithms).
///
/// Tools:
///   get_moon_phase  — lunar phase name, illumination %, days into cycle
///   get_sun_times   — sunrise, solar noon, sunset for a lat/lon
///   get_dawn_dusk   — civil and nautical twilight times
enum AstralTools {

    static func register() {
        registerMoonPhase()
        registerSunTimes()
        registerDawnDusk()
    }

    // MARK: - Moon phase

    private static func registerMoonPhase() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "get_moon_phase",
            description:   "Returns the current lunar phase name, illumination percentage, and days into the cycle.",
            parametersDoc: "(no parameters — uses today's date)",
            argsExample:   "{}",
            execute: { _ in
                let r = moonPhase()
                return .text("""
{"phase":"\(r.name)","illumination_pct":\(r.illuminationPct),"days_into_cycle":\(String(format:"%.1f",r.daysIntoCycle)),"days_to_full":\(String(format:"%.1f",r.daysToFull)),"days_to_new":\(String(format:"%.1f",r.daysToNew))}
""".trimmingCharacters(in: .newlines))
            }
        ))
    }

    private static func registerSunTimes() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "get_sun_times",
            description:   "Returns sunrise, solar noon, and sunset times for the given coordinates and today's date.",
            parametersDoc: "latitude: number, longitude: number",
            argsExample:   "{\"latitude\":37.7749,\"longitude\":-122.4194}",
            execute: { args in
                guard let lat = args.toolDouble("latitude") else { return .text(#"{"error":"latitude required"}"#) }
                guard let lon = args.toolDouble("longitude") else { return .text(#"{"error":"longitude required"}"#) }
                let tz     = TimeZone.current
                let cal    = Calendar.current
                let now    = Date()
                let year   = cal.component(.year,  from: now)
                let month  = cal.component(.month, from: now)
                let day    = cal.component(.day,   from: now)
                let tzOff  = Double(tz.secondsFromGMT()) / 3600.0
                guard let times = sunTimes(lat: lat, lon: lon, year: year, month: month, day: day, tzOffset: tzOff) else {
                    return .text(#"{"error":"Sun does not rise or set at this location on this date (polar day/night)"}"#)
                }
                return .text("""
{"sunrise":"\(times.sunrise)","solar_noon":"\(times.solarNoon)","sunset":"\(times.sunset)","day_length_minutes":\(times.dayLengthMinutes)}
""".trimmingCharacters(in: .newlines))
            }
        ))
    }

    private static func registerDawnDusk() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "get_dawn_dusk",
            description:   "Returns civil dawn/dusk and nautical dawn/dusk for today at the given coordinates.",
            parametersDoc: "latitude: number, longitude: number",
            argsExample:   "{\"latitude\":37.7749,\"longitude\":-122.4194}",
            execute: { args in
                guard let lat = args.toolDouble("latitude") else { return .text(#"{"error":"latitude required"}"#) }
                guard let lon = args.toolDouble("longitude") else { return .text(#"{"error":"longitude required"}"#) }
                let tz    = TimeZone.current
                let cal   = Calendar.current
                let now   = Date()
                let year  = cal.component(.year,  from: now)
                let month = cal.component(.month, from: now)
                let day   = cal.component(.day,   from: now)
                let tzOff = Double(tz.secondsFromGMT()) / 3600.0
                let civil    = twilightTimes(lat: lat, lon: lon, year: year, month: month, day: day, tzOffset: tzOff, depression: 6.0)
                let nautical = twilightTimes(lat: lat, lon: lon, year: year, month: month, day: day, tzOffset: tzOff, depression: 12.0)
                return .text("""
{"civil_dawn":"\(civil?.dawn ?? "N/A")","civil_dusk":"\(civil?.dusk ?? "N/A")","nautical_dawn":"\(nautical?.dawn ?? "N/A")","nautical_dusk":"\(nautical?.dusk ?? "N/A")"}
""".trimmingCharacters(in: .newlines))
            }
        ))
    }

    // MARK: - Moon phase math

    private struct MoonPhaseResult {
        let name: String; let illuminationPct: Int
        let daysIntoCycle: Double; let daysToFull: Double; let daysToNew: Double
    }

    private static func moonPhase() -> MoonPhaseResult {
        let refNewMoonJd  = 2451549.5 + 0.759722   // Jan 6 2000 new moon
        let synodicPeriod = 29.53058868
        let nowJd         = julianDay()
        let cycle = ((nowJd - refNewMoonJd).truncatingRemainder(dividingBy: synodicPeriod) + synodicPeriod)
                        .truncatingRemainder(dividingBy: synodicPeriod)

        let angle        = cycle / synodicPeriod * 2 * .pi
        let illumination = Int(((1 - cos(angle)) / 2 * 100).rounded()).clamped(to: 0...100)

        let name: String
        switch cycle {
        case ..<1.85:  name = "New Moon"
        case ..<7.38:  name = "Waxing Crescent"
        case ..<9.22:  name = "First Quarter"
        case ..<14.77: name = "Waxing Gibbous"
        case ..<16.61: name = "Full Moon"
        case ..<22.15: name = "Waning Gibbous"
        case ..<24.0:  name = "Last Quarter"
        default:       name = "Waning Crescent"
        }

        let daysToFull = cycle < 14.77 ? 14.77 - cycle : synodicPeriod - cycle + 14.77
        let daysToNew  = synodicPeriod - cycle
        return MoonPhaseResult(name: name, illuminationPct: illumination,
                               daysIntoCycle: cycle, daysToFull: daysToFull, daysToNew: daysToNew)
    }

    // MARK: - Sun times math (Jean Meeus / USNO)

    private struct SunTimesResult {
        let sunrise: String; let solarNoon: String
        let sunset: String; let dayLengthMinutes: Int
    }

    private static func sunTimes(lat: Double, lon: Double,
                                  year: Int, month: Int, day: Int,
                                  tzOffset: Double) -> SunTimesResult? {
        guard let rise = sunEvent(lat: lat, lon: lon, year: year, month: month, day: day,
                                   tzOffset: tzOffset, rising: true,  zenith: 90.833),
              let set  = sunEvent(lat: lat, lon: lon, year: year, month: month, day: day,
                                   tzOffset: tzOffset, rising: false, zenith: 90.833) else { return nil }
        let noon   = (rise + set) / 2.0
        let dayLen = Int(((set - rise) * 60).rounded())
        return SunTimesResult(sunrise: hhMM(rise), solarNoon: hhMM(noon),
                              sunset: hhMM(set), dayLengthMinutes: dayLen)
    }

    private struct TwilightResult { let dawn: String; let dusk: String }

    private static func twilightTimes(lat: Double, lon: Double,
                                       year: Int, month: Int, day: Int,
                                       tzOffset: Double,
                                       depression: Double) -> TwilightResult? {
        let z = 90.0 + depression
        guard let dawn = sunEvent(lat: lat, lon: lon, year: year, month: month, day: day,
                                   tzOffset: tzOffset, rising: true,  zenith: z),
              let dusk = sunEvent(lat: lat, lon: lon, year: year, month: month, day: day,
                                   tzOffset: tzOffset, rising: false, zenith: z) else { return nil }
        return TwilightResult(dawn: hhMM(dawn), dusk: hhMM(dusk))
    }

    private static func sunEvent(lat: Double, lon: Double,
                                  year: Int, month: Int, day: Int,
                                  tzOffset: Double,
                                  rising: Bool, zenith: Double) -> Double? {
        let n1 = floor(275.0 * Double(month) / 9)
        let n2 = floor((Double(month) + 9.0) / 12)
        let n3 = 1 + floor((Double(year) - 4 * floor(Double(year) / 4) + 2) / 3)
        let n  = n1 - n2 * n3 + Double(day) - 30

        let lngHour = lon / 15.0
        let t = rising ? n + (6 - lngHour) / 24.0 : n + (18 - lngHour) / 24.0

        let m  = (0.9856 * t - 3.289).toRad()
        var l  = m.toDeg() + 1.916 * sin(m) + 0.020 * sin(2 * m) + 282.634
        l = l.normDeg()

        var ra = atan(0.91764 * tan(l.toRad())).toDeg().normDeg()
        let lQuad  = floor(l  / 90) * 90
        let raQuad = floor(ra / 90) * 90
        ra = (ra + lQuad - raQuad) / 15.0

        let sinDec = 0.39782 * sin(l.toRad())
        let cosDec = cos(asin(sinDec))
        let cosH   = (cos(zenith.toRad()) - sinDec * sin(lat.toRad())) / (cosDec * cos(lat.toRad()))
        if cosH < -1 || cosH > 1 { return nil }

        let h  = rising ? 360 - acos(cosH).toDeg() : acos(cosH).toDeg()
        let hh = h / 15.0
        let t2 = hh + ra - 0.06571 * t - 6.622
        var ut = t2 - lngHour + tzOffset
        ut = ((ut.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        return ut
    }

    // MARK: - Helpers

    private static func julianDay() -> Double {
        Date().timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    private static func hhMM(_ decimalHours: Double) -> String {
        let total = ((decimalHours.truncatingRemainder(dividingBy: 24)) + 24)
                        .truncatingRemainder(dividingBy: 24)
        let hh = Int(total)
        let mm = min(Int((total - Double(hh)) * 60 + 0.5), 59)
        return String(format: "%02d:%02d", hh, mm)
    }
}

// MARK: - Double extensions (file-private)

private extension Double {
    func toRad()  -> Double { self * .pi / 180 }
    func toDeg()  -> Double { self * 180 / .pi }
    func normDeg() -> Double { (self.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
