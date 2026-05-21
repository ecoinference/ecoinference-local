import 'package:dio/dio.dart';

/// A single result item from the Brave Search API.
class BraveSearchResult {
  const BraveSearchResult({
    required this.title,
    required this.url,
    required this.description,
  });

  final String title;
  final String url;
  final String description;

  /// Returns a compact text representation suitable for inclusion in an
  /// LLM context window.
  String toContextString() => '**$title**\n$url\n$description';
}

/// Wraps the Brave Search REST API.
///
/// Free tier: 2 000 queries/month. Requires an API key from
/// https://brave.com/search/api/
///
/// Usage:
/// ```dart
/// final results = await WebSearchService.search('flutter state management', apiKey);
/// ```
class WebSearchService {
  WebSearchService._();

  static const _baseUrl = 'https://api.search.brave.com/res/v1/web/search';
  static const _defaultCount = 5;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  /// Searches the web via Brave Search and returns up to [count] results.
  ///
  /// Throws a [WebSearchException] on API errors or network failures.
  static Future<List<BraveSearchResult>> search(
    String query, {
    required String apiKey,
    int count = _defaultCount,
  }) async {
    if (apiKey.isEmpty) {
      throw const WebSearchException('Brave Search API key is not configured.');
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _baseUrl,
        queryParameters: {
          'q': query,
          'count': count,
          'safesearch': 'moderate',
          'text_decorations': false,
          'result_filter': 'web',
        },
        options: Options(headers: {
          'X-Subscription-Token': apiKey,
          'Accept': 'application/json',
        }),
      );

      final body = response.data;
      if (body == null) throw const WebSearchException('Empty response from Brave Search.');

      final web = body['web'] as Map<String, dynamic>?;
      final results = web?['results'] as List<dynamic>? ?? [];

      return results.map((r) {
        final item = r as Map<String, dynamic>;
        return BraveSearchResult(
          title:       (item['title']       as String? ?? '').trim(),
          url:         (item['url']         as String? ?? '').trim(),
          description: (item['description'] as String? ?? '').trim(),
        );
      }).toList();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const WebSearchException(
            'Invalid or missing Brave Search API key (401/403).');
      }
      if (status == 429) {
        throw const WebSearchException(
            'Brave Search rate limit exceeded. Try again later.');
      }
      throw WebSearchException('Network error: ${e.message}');
    }
  }
}

class WebSearchException implements Exception {
  const WebSearchException(this.message);
  final String message;
  @override
  String toString() => 'WebSearchException: $message';
}
