import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../tools/tool_definition.dart';

// ── Copy helper ───────────────────────────────────────────────────────────────

void _copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Copied to clipboard'),
      duration: Duration(seconds: 2),
    ),
  );
}

/// Small copy icon button used across all bubble types.
Widget _copyButton(BuildContext context, String text, {Color? color}) {
  return IconButton(
    icon: const Icon(Icons.copy_outlined),
    iconSize: 15,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    tooltip: 'Copy',
    color: color ?? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
    onPressed: () => _copyToClipboard(context, text),
  );
}

// ── Main entry point ──────────────────────────────────────────────────────────

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onViewChart});

  final ChatMessage message;

  /// Called when user taps "View Chart" on an HTML tool result.
  final VoidCallback? onViewChart;

  @override
  Widget build(BuildContext context) {
    if (message.isTool) {
      return _ToolBubble(message: message, onViewChart: onViewChart);
    }

    final theme = Theme.of(context);
    final isUser = message.isUser;

    // User bubbles are right-aligned and capped at 78% width.
    // Assistant bubbles expand to fill all available width so long responses
    // are never clipped.
    final double maxWidth = isUser
        ? MediaQuery.of(context).size.width * 0.78
        : double.infinity;

    // Decode attached image bytes once for this build pass.
    final Uint8List? attachedBytes = _decodeAttachedImage(message);

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: EdgeInsets.only(
            bottom: 2,
            left: isUser ? 48 : 0,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
          ),
          // Clip so the image respects the bubble's rounded corners.
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Attached image thumbnail (current session only).
              if (attachedBytes != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Image.memory(
                    attachedBytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              // Text — omit padding-only container when content is empty.
              if (message.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: SelectableText(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Copy button sits below the bubble, aligned to its edge.
        if (message.content.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              bottom: 4,
              left: isUser ? 0 : 4,
              right: isUser ? 4 : 0,
            ),
            child: _copyButton(
              context,
              message.content,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Safely decodes the base64 JPEG attached to a user message.
/// Returns null if no image is attached or decoding fails.
Uint8List? _decodeAttachedImage(ChatMessage message) {
  final b64 = message.attachedImageBase64;
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

// ── Tool bubble dispatcher ────────────────────────────────────────────────────

class _ToolBubble extends StatelessWidget {
  const _ToolBubble({required this.message, this.onViewChart});
  final ChatMessage message;
  final VoidCallback? onViewChart;

  @override
  Widget build(BuildContext context) {
    if (message.imageDataUrl != null) {
      return _ImageToolBubble(message: message);
    }
    if (message.htmlContent != null) {
      return _HtmlToolBubble(message: message, onViewChart: onViewChart);
    }
    // DEBUG bubble — full-width selectable text. TODO: remove before release.
    if (message.toolName == ToolNames.parserDebug) {
      return _DebugToolBubble(message: message);
    }
    return _ChipToolBubble(message: message);
  }
}

// ── Debug bubble ──────────────────────────────────────────────────────────────

/// Full-width debug bubble for parser diagnostics. TODO: remove before release.
class _DebugToolBubble extends StatelessWidget {
  const _DebugToolBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message.toolName ?? '',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error),
                ),
              ),
              _copyButton(context, message.content,
                  color: theme.colorScheme.error.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            message.content,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plain-text chip ───────────────────────────────────────────────────────────

/// Inline chip for plain-text tool results (including errors and status).
class _ChipToolBubble extends StatelessWidget {
  const _ChipToolBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = message.content.endsWith('…');
    final label =
        '${message.toolName != null ? "[${message.toolName}] " : ""}${message.content}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: EdgeInsets.only(
            left: 12,
            // Reduce right padding when showing the copy button so it fits snugly.
            right: isRunning ? 12 : 4,
            top: 6,
            bottom: 6,
          ),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: theme.colorScheme.secondary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Leading icon / spinner
              if (isRunning)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.secondary),
                )
              else
                Icon(Icons.build_outlined,
                    size: 13, color: theme.colorScheme.secondary),
              const SizedBox(width: 6),
              // Label — constrained so very long errors don't overflow
              Flexible(
                child: Text(
                  label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              // Explicit copy button — only on completed chips
              if (!isRunning)
                _copyButton(context, message.content),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Image bubble ──────────────────────────────────────────────────────────────

/// Displays a matplotlib PNG inline in the chat.
class _ImageToolBubble extends StatelessWidget {
  const _ImageToolBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataUrl = message.imageDataUrl!;

    final commaIdx = dataUrl.indexOf(',');
    if (commaIdx == -1) {
      return _ChipToolBubble(
          message: ChatMessage(
              role: MessageRole.tool,
              content: 'Image decode error.',
              toolName: message.toolName));
    }

    final Uint8List bytes;
    try {
      bytes = base64Decode(dataUrl.substring(commaIdx + 1));
    } catch (_) {
      return _ChipToolBubble(
          message: ChatMessage(
              role: MessageRole.tool,
              content: 'Image decode error.',
              toolName: message.toolName));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.toolName != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_outlined,
                      size: 13, color: theme.colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text('[${message.toolName}]',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.secondary)),
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }
}

// ── HTML / chart chip ─────────────────────────────────────────────────────────

/// Chip for Plotly HTML results with "View Chart" and copy buttons.
class _HtmlToolBubble extends StatelessWidget {
  const _HtmlToolBubble({required this.message, this.onViewChart});
  final ChatMessage message;
  final VoidCallback? onViewChart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: theme.colorScheme.secondary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_graph_outlined,
                  size: 14, color: theme.colorScheme.secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '[${message.toolName ?? "tool"}] ${message.content}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              TextButton(
                onPressed: onViewChart,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                child: const Text('View Chart'),
              ),
              _copyButton(context, message.content),
            ],
          ),
        ),
      ),
    );
  }
}
