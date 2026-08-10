import CoreLocation
import Foundation

// MARK: - LocationResult

struct LocationResult {
    let latitude:        Double
    let longitude:       Double
    let timezone:        TimeZone
    let timezoneOffset:  Double   // UTC offset in hours, e.g. -5.0 for CDT

    // ── Python preamble ───────────────────────────────────────────────────────
    /// Injected before generated Python code so user_latitude / user_longitude
    /// / user_timezone are already defined when the snippet runs.
    var pythonPreamble: String {
        let offsetHours = timezoneOffset
        return """
user_latitude = \(String(format: "%.6f", latitude))
user_longitude = \(String(format: "%.6f", longitude))
user_timezone_offset = \(String(format: "%.1f", offsetHours))
import datetime
import datetime as _dt
user_timezone = _dt.timezone(_dt.timedelta(hours=\(String(format: "%.1f", offsetHours))))

"""
    }

    // ── Plain-text context ────────────────────────────────────────────────────
    /// Human-readable block injected into the chat system prompt.
    var chatContext: String {
        let fmt  = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .short
        fmt.timeZone  = timezone
        let now  = fmt.string(from: Date())
        return "[Device context: \(now). Approximate location: \(String(format: "%.4f", latitude))°N, \(String(format: "%.4f", longitude))°E. Timezone: \(timezone.identifier).]"
    }

    /// Tool-result string fed back to the model after a get_location call.
    var toolResult: String {
        "lat=\(String(format: "%.6f", latitude)), lon=\(String(format: "%.6f", longitude)), " +
        "timezone=\(timezone.identifier), utcOffset=\(String(format: "%.1f", timezoneOffset))h"
    }
}

// MARK: - LocationService

/// Thin async wrapper around CLLocationManager.
/// Each call to requestLocation() fires a fresh one-shot location request.
final class LocationService: NSObject {

    static let shared = LocationService()

    private override init() {
        // CLLocationManager MUST be created on the main thread.
        // If the singleton is first accessed off-main (e.g. from Task.detached),
        // force creation onto main now via a synchronous hop.
        if Thread.isMainThread {
            _manager = CLLocationManager()
        } else {
            var m: CLLocationManager!
            DispatchQueue.main.sync { m = CLLocationManager() }
            _manager = m
        }
        super.init()
        dlog("LocationService.init: CLLocationManager created (main=\(Thread.isMainThread))")
    }

    private let _manager: CLLocationManager
    private var manager: CLLocationManager { _manager }
    private var pendingContinuation: CheckedContinuation<CLLocation, Error>?

    // ── Public API ────────────────────────────────────────────────────────────

    /// Requests a single location fix. Throws if permission is denied or times out.
    func requestLocation() async throws -> LocationResult {
        let location = try await fetchRawLocation()
        let tz = TimeZone.current
        let offsetSecs = Double(tz.secondsFromGMT())
        let offsetHours = offsetSecs / 3600.0
        return LocationResult(
            latitude:       location.coordinate.latitude,
            longitude:      location.coordinate.longitude,
            timezone:       tz,
            timezoneOffset: offsetHours
        )
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func fetchRawLocation() async throws -> CLLocation {
        let callerThread = Thread.isMainThread ? "main" : "background"
        dlog("LocationService.fetchRawLocation: entered on \(callerThread) thread")
        return try await withCheckedThrowingContinuation { continuation in
            // CLLocationManager MUST be driven from a thread with a run loop.
            // The Swift cooperative thread pool (Task.detached) has no run loop,
            // so delegate callbacks never fire from there.  Dispatching to the
            // main queue gives us a guaranteed run loop and is safe because
            // CLLocationManager operations are lightweight.
            DispatchQueue.main.async { [self] in
                self.pendingContinuation = continuation
                manager.delegate         = self
                manager.desiredAccuracy  = kCLLocationAccuracyHundredMeters

                let status = manager.authorizationStatus
                dlog("LocationService.fetchRawLocation (main): authorizationStatus=\(status.rawValue) (\(Self.statusName(status)))")

                switch status {
                case .notDetermined:
                    dlog("LocationService.fetchRawLocation (main): calling requestWhenInUseAuthorization()")
                    manager.requestWhenInUseAuthorization()
                    // delegate will call requestLocation() once auth is granted
                case .authorizedWhenInUse, .authorizedAlways:
                    dlog("LocationService.fetchRawLocation (main): authorized — calling requestLocation()")
                    manager.requestLocation()
                case .denied, .restricted:
                    dlog("LocationService.fetchRawLocation (main): denied/restricted — resuming with error")
                    let err = NSError(
                        domain: kCLErrorDomain,
                        code: CLError.denied.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "Location access denied. Enable it in Settings > Privacy > Location Services."]
                    )
                    continuation.resume(throwing: err)
                    pendingContinuation = nil
                @unknown default:
                    dlog("LocationService.fetchRawLocation (main): unknown status — calling requestLocation()")
                    manager.requestLocation()
                }
            }
        }
    }

    private static func statusName(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined:       return "notDetermined"
        case .restricted:          return "restricted"
        case .denied:              return "denied"
        case .authorizedAlways:    return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default:          return "unknown(\(s.rawValue))"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        dlog("LocationService.didUpdateLocations: \(locations.count) location(s)")
        guard let location = locations.first else {
            dlog("LocationService.didUpdateLocations: no locations in array — ignoring")
            return
        }
        dlog("LocationService.didUpdateLocations: resuming continuation with fix")
        pendingContinuation?.resume(returning: location)
        pendingContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        dlog("LocationService.didFailWithError: \(error.localizedDescription)")
        pendingContinuation?.resume(throwing: error)
        pendingContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        dlog("LocationService.didChangeAuthorization: status=\(LocationService.statusName(status))")
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if pendingContinuation != nil {
                dlog("LocationService.didChangeAuthorization: authorized — calling requestLocation()")
                manager.requestLocation()
            }
        case .denied, .restricted:
            dlog("LocationService.didChangeAuthorization: denied — resuming with error")
            let err = NSError(
                domain: kCLErrorDomain,
                code: CLError.denied.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Location access denied."]
            )
            pendingContinuation?.resume(throwing: err)
            pendingContinuation = nil
        default:
            dlog("LocationService.didChangeAuthorization: unhandled status \(status.rawValue) — no action")
            break
        }
    }
}
