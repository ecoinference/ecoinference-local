import 'package:dio/dio.dart';

/// Fetches current weather conditions from open-meteo.com (free, no API key).
///
/// Returns a compact context string suitable for system prompt injection, or
/// `null` if the fetch fails (network unavailable, timeout, etc.).
class WeatherService {
  WeatherService._();

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  /// Fetches current conditions + today's high/low/rain chance for [lat]/[lon].
  ///
  /// Returns a formatted string, e.g.:
  /// ```
  /// Conditions: Partly cloudy, 68°F (feels like 65°F)
  /// Humidity: 55% | Wind: 8 mph NW
  /// Today: High 72°F / Low 55°F | Rain chance: 10%
  /// ```
  static Future<String?> getWeather(double lat, double lon) async {
    try {
      final response = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': lat,
          'longitude': lon,
          'current': [
            'temperature_2m',
            'apparent_temperature',
            'relative_humidity_2m',
            'weather_code',
            'wind_speed_10m',
            'wind_direction_10m',
          ].join(','),
          'daily': [
            'temperature_2m_max',
            'temperature_2m_min',
            'precipitation_probability_max',
          ].join(','),
          'temperature_unit': 'fahrenheit',
          'wind_speed_unit': 'mph',
          'forecast_days': 1,
          'timezone': 'auto',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>;

      final temp = (current['temperature_2m'] as num).round();
      final feelsLike = (current['apparent_temperature'] as num).round();
      final humidity = (current['relative_humidity_2m'] as num).round();
      final windSpeed = (current['wind_speed_10m'] as num).round();
      final windDir = _windDirection(current['wind_direction_10m'] as num);
      final code = current['weather_code'] as int;
      final condition = _wmoDescription(code);

      final high = (daily['temperature_2m_max'][0] as num).round();
      final low = (daily['temperature_2m_min'][0] as num).round();
      final rainChance = (daily['precipitation_probability_max'][0] as num).round();

      return 'Conditions: $condition, $temp°F (feels like $feelsLike°F)\n'
          'Humidity: $humidity% | Wind: $windSpeed mph $windDir\n'
          'Today: High $high°F / Low $low°F | Rain chance: $rainChance%';
    } catch (_) {
      return null; // silently skip — weather is optional context
    }
  }

  // ── WMO weather interpretation codes ─────────────────────────────────────
  // https://open-meteo.com/en/docs — "WMO Weather interpretation codes"

  static String _wmoDescription(int code) => switch (code) {
    0           => 'Clear sky',
    1           => 'Mainly clear',
    2           => 'Partly cloudy',
    3           => 'Overcast',
    45 || 48    => 'Foggy',
    51          => 'Light drizzle',
    53          => 'Moderate drizzle',
    55          => 'Dense drizzle',
    61          => 'Slight rain',
    63          => 'Moderate rain',
    65          => 'Heavy rain',
    71          => 'Slight snow',
    73          => 'Moderate snow',
    75          => 'Heavy snow',
    77          => 'Snow grains',
    80          => 'Slight rain showers',
    81          => 'Moderate rain showers',
    82          => 'Violent rain showers',
    85 || 86    => 'Snow showers',
    95          => 'Thunderstorm',
    96 || 99    => 'Thunderstorm with hail',
    _           => 'Unknown conditions',
  };

  // ── Wind direction ────────────────────────────────────────────────────────

  static String _windDirection(num degrees) {
    const dirs = ['N','NE','E','SE','S','SW','W','NW'];
    return dirs[((degrees / 45).round() % 8).toInt()];
  }
}
