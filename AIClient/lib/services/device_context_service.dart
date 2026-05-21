import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Collects current device state — date/time, battery, network — and returns
/// a compact context block for injection into the LLM system prompt.
///
/// All errors are caught internally; a partial result is always returned.
class DeviceContextService {
  DeviceContextService._();

  static final _battery = Battery();
  static final _connectivity = Connectivity();

  /// Returns a formatted multi-line context string, e.g.:
  ///
  /// ```
  /// Date: Monday, 19 May 2026
  /// Time: 10:34 AM (UTC-5)
  /// Battery: 87%
  /// Network: WiFi
  /// ```
  static Future<String> getContext() async {
    final now = DateTime.now();

    final results = await Future.wait([
      _getBatteryString(),
      _getNetworkString(),
    ]);

    return 'Date: ${_formatDate(now)}\n'
        'Time: ${_formatTime(now)} (${_tzLabel(now)})\n'
        'Battery: ${results[0]}\n'
        'Network: ${results[1]}';
  }

  // ── Date / time helpers ───────────────────────────────────────────────────

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _formatDate(DateTime dt) =>
      '${_weekdays[dt.weekday - 1]}, ${dt.day} ${_months[dt.month]} ${dt.year}';

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  static String _tzLabel(DateTime dt) {
    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs();
    final mins = (offset.inMinutes.abs() % 60);
    return mins == 0 ? 'UTC$sign$hours' : 'UTC$sign$hours:${mins.toString().padLeft(2, '0')}';
  }

  // ── Battery ───────────────────────────────────────────────────────────────

  static Future<String> _getBatteryString() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final suffix = switch (state) {
        BatteryState.charging => ' (charging)',
        BatteryState.full     => ' (full)',
        _                     => '',
      };
      return '$level%$suffix';
    } catch (_) {
      return 'unknown';
    }
  }

  // ── Network ───────────────────────────────────────────────────────────────

  static Future<String> _getNetworkString() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // checkConnectivity returns List<ConnectivityResult> in v6+
      if (results.contains(ConnectivityResult.wifi))   return 'WiFi';
      if (results.contains(ConnectivityResult.mobile)) return 'Cellular';
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      return 'Offline';
    } catch (_) {
      return 'unknown';
    }
  }
}
