import 'package:url_launcher/url_launcher.dart';

import 'tool_definition.dart';
import 'tool_result.dart';

/// Registers URL/app-launching tools into [ToolRegistry].
void registerUrlTools() {
  ToolRegistry.register(ToolDefinition(
    name: 'launch_url',
    description:
        'Open a URL in the browser or launch another app using its URL scheme. '
        'Use for web URLs (https://…) or deep links into installed apps '
        '(maps://, tel://, mailto://, spotify://, etc.).',
    parametersDoc: 'url: string',
    argsExample: '{"url": "https://example.com"}',
    // Confirmation is handled inside execute: only for non-http(s) schemes.
    requiresConfirmation: false,
    execute: _launchUrl,
  ));
}

Future<ToolResult> _launchUrl(Map<String, dynamic> args) async {
  final rawUrl = (args['url'] as String? ?? '').trim();
  if (rawUrl.isEmpty) {
    return const TextToolResult('Error: url parameter is required.');
  }

  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    return TextToolResult('Error: "$rawUrl" is not a valid URL.');
  }

  // Require confirmation before opening non-web URLs (app-to-app schemes).
  // Web URLs (http/https) open silently — they're read-only, low risk.
  final isWebUrl =
      uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == '';
  if (!isWebUrl) {
    // Use url_launcher's canLaunchUrl as a quick sanity check before showing
    // the dialog — avoids confirming something that will fail anyway.
    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      return const TextToolResult(
          'Cannot open — no app registered for that scheme.');
    }
    // Confirmation is injected by ChatScreen via ToolDefinition.execute wrapping;
    // here we delegate to the internal custom-confirm pattern used by web_search:
    // simply call the function — ChatScreen checks requiresConfirmation first
    // which is false, so we must confirm ourselves via stored callback.
    final confirmed = await _confirmCallback?.call(rawUrl) ?? true;
    if (!confirmed) {
      return const TextToolResult('Launch cancelled by user.');
    }
  }

  try {
    final launched = await launchUrl(
      uri,
      mode: isWebUrl
          ? LaunchMode.externalApplication
          : LaunchMode.externalApplication,
    );
    if (!launched) {
      return TextToolResult('Could not open "$rawUrl".');
    }
    return TextToolResult('Opened: $rawUrl');
  } catch (e) {
    return TextToolResult('Error opening URL: $e');
  }
}

// ── Confirmation callback (set by ChatScreen) ─────────────────────────────────

/// Called when a non-http URL needs user confirmation before opening.
/// Set this from ChatScreen to display a dialog.
Future<bool> Function(String url)? _confirmCallback;

/// Register the confirmation dialog callback from ChatScreen.
void setUrlLaunchConfirmCallback(Future<bool> Function(String url) fn) {
  _confirmCallback = fn;
}
