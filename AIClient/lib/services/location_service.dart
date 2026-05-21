import 'package:geolocator/geolocator.dart';

import '../config/debug_config.dart';

/// Wraps [Geolocator] with a simple one-shot API used by the Python tool runner.
///
/// Returns the device GPS fix as a [DeviceLocation], or `null` when:
///   - Location services are disabled
///   - The user denies permission (including "deny forever")
///   - The fix times out (5 s)
///   - Any unexpected error occurs
///
/// Never throws — always returns a value or null.
class LocationService {
  LocationService._();

  /// Requests location permission if needed and returns the current position.
  ///
  /// The [timeout] defaults to 5 seconds — long enough for a cached GPS fix,
  /// short enough not to stall the tool pipeline noticeably.
  static Future<DeviceLocation?> getLocation(
      {Duration timeout = const Duration(seconds: 5)}) async {
    // ── Mock mode (debug only) ─────────────────────────────────────────────
    // Returns Swisher Iowa coords so location-based tool tests are reproducible
    // without needing a real GPS fix. Flip kUseMockLocation in debug_config.dart.
    if (kUseMockLocation) {
      return const DeviceLocation(
        latitude: kMockLatitude,
        longitude: kMockLongitude,
        accuracy: 0,
        timezoneOffsetHours: kMockTimezoneOffset,
      );
    }

    try {
      // 1. Check location services
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // 2. Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      // 3. Get position — accept last-known fix first for speed
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      ).timeout(timeout);

      // 4. Capture device UTC offset at the moment of the fix.
      //    This is injected as user_timezone_offset (hours) into Python so the
      //    model never needs to look up a timezone from coordinates.
      final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      final offsetHours = offsetMinutes / 60.0;

      return DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timezoneOffsetHours: offsetHours,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Lightweight value object — avoids exposing [Position] outside this service.
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timezoneOffsetHours,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in metres (approximate).
  final double accuracy;

  /// Device UTC offset in fractional hours (e.g. -5.0 for CDT, 5.5 for IST).
  /// Derived from [DateTime.now().timeZoneOffset] at the time of the GPS fix.
  final double timezoneOffsetHours;

  /// Python preamble injected at the top of every tool execution when location
  /// is available. Provides:
  ///   user_latitude          — GPS latitude (float)
  ///   user_longitude         — GPS longitude (float)
  ///   user_timezone_offset   — UTC offset in hours (float, e.g. -5.0)
  ///   user_timezone          — datetime.timezone built from the offset
  ///
  /// The model can use user_timezone directly as tzinfo in astral / datetime
  /// calls without importing zoneinfo or looking up a named timezone.
  String get pythonPreamble {
    final sign = timezoneOffsetHours >= 0 ? '+' : '';
    return 'import datetime as _dt\n'
        'user_latitude = $latitude  # device GPS\n'
        'user_longitude = $longitude  # device GPS\n'
        'user_timezone_offset = $timezoneOffsetHours  # UTC offset in hours\n'
        'user_timezone = _dt.timezone(_dt.timedelta(hours=$timezoneOffsetHours))  '
        '# e.g. UTC$sign$timezoneOffsetHours\n\n';
  }

  @override
  String toString() =>
      'DeviceLocation(lat=$latitude, lon=$longitude, '
      'accuracy=${accuracy.toStringAsFixed(0)}m, '
      'tz=UTC${timezoneOffsetHours >= 0 ? '+' : ''}$timezoneOffsetHours)';
}
