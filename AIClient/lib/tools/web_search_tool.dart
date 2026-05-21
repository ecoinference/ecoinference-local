import '../services/search_confirmation_service.dart';
import '../services/web_search_service.dart';
import 'tool_definition.dart';
import 'tool_result.dart';

/// Registers the `web_search` tool into [ToolRegistry].
///
/// [apiKey] is the Brave Search API subscription token.  Pass an empty string
/// if none is configured — the tool will then return a helpful error.
///
/// Call once from ChatScreen.initState after setting the
/// [SearchConfirmationService] dialog callback.
void registerWebSearchTool({required String apiKey}) {
  ToolRegistry.register(ToolDefinition(
    name: 'web_search',
    description:
        'Search the internet using Brave Search and return the top results. '
        'Use this when the user asks about recent events, news, or information '
        'that may not be in your training data.',
    parametersDoc: 'query: string',
    argsExample: '{"query": "latest news about AI"}',
    // Confirmation is handled inside execute (conditionally, based on
    // SearchConfirmationService state), so requiresConfirmation stays false.
    requiresConfirmation: false,
    execute: (args) => _webSearch(args, apiKey),
  ));
}

Future<ToolResult> _webSearch(Map<String, dynamic> args, String apiKey) async {
  final query = (args['query'] as String? ?? '').trim();
  if (query.isEmpty) {
    return const TextToolResult('Error: query parameter is required.');
  }

  // Conditional confirmation: shows dialog only when topic changed or >1 hour.
  final allowed = await SearchConfirmationService.requestConfirmation(query);
  if (!allowed) {
    return const TextToolResult('Web search cancelled by user.');
  }

  try {
    final results = await WebSearchService.search(query, apiKey: apiKey);

    if (results.isEmpty) {
      return const TextToolResult('No results found for that query.');
    }

    final buf = StringBuffer('Web search results for "$query":\n\n');
    for (var i = 0; i < results.length; i++) {
      buf
        ..write('${i + 1}. ')
        ..writeln(results[i].toContextString())
        ..writeln();
    }

    return TextToolResult(buf.toString().trimRight());
  } on WebSearchException catch (e) {
    return TextToolResult('Web search error: ${e.message}');
  } catch (e) {
    return TextToolResult('Web search unexpected error: $e');
  }
}
