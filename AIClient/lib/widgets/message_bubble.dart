import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/chat_message.dart';

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: EdgeInsets.only(
          bottom: 8,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        child: SelectableText(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ── Tool bubble ───────────────────────────────────────────────────────────────

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
    return _ChipToolBubble(message: message);
  }
}

/// Inline chip shown for plain-text tool results.
class _ChipToolBubble extends StatelessWidget {
  const _ChipToolBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = message.content.endsWith('…');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRunning)
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.colorScheme.secondary),
                )
              else
                Icon(Icons.build_outlined, size: 13, color: theme.colorScheme.secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${message.toolName != null ? "[${message.toolName}] " : ""}${message.content}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays a matplotlib PNG inline in the chat.
class _ImageToolBubble extends StatelessWidget {
  const _ImageToolBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataUrl = message.imageDataUrl!;

    // Strip the "data:image/png;base64," prefix
    final commaIdx = dataUrl.indexOf(',');
    if (commaIdx == -1) {
      return _ChipToolBubble(message: ChatMessage(
        role: MessageRole.tool,
        content: 'Image decode error.',
        toolName: message.toolName,
      ));
    }

    final Uint8List bytes;
    try {
      bytes = base64Decode(dataUrl.substring(commaIdx + 1));
    } catch (_) {
      return _ChipToolBubble(message: ChatMessage(
        role: MessageRole.tool,
        content: 'Image decode error.',
        toolName: message.toolName,
      ));
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
                  Icon(Icons.bar_chart_outlined, size: 13, color: theme.colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text('[${message.toolName}]',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
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

/// Chip for Plotly HTML results with a "View Chart" button.
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_graph_outlined, size: 14, color: theme.colorScheme.secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '[${message.toolName ?? "run_python"}] ${message.content}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onViewChart,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                child: const Text('View Chart'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
