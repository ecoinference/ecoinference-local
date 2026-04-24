import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';
import '../../models/server_config.dart';
import '../../services/api_service.dart';
import '../../widgets/message_bubble.dart';
import '../connection/connection_screen.dart';

/// Main chat interface. Streams tokens from the server as they arrive.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.config});

  final ServerConfig config;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = false;
  late ApiService _api;
  String? _systemPrompt;

  /// Accumulates tokens while a streaming response is in flight.
  /// Null when no stream is active; empty string before the first token arrives.
  String? _streamingContent;
  StreamSubscription<String>? _streamSub;

  static const _kSystemPromptKey = 'system_prompt';

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.config);
    _loadSystemPrompt();
  }

  Future<void> _loadSystemPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kSystemPromptKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _systemPrompt = saved);
    }
  }

  Future<void> _saveSystemPrompt(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_kSystemPromptKey);
    } else {
      await prefs.setString(_kSystemPromptKey, value);
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Sending ─────────────────────────────────────────────────────────────────

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    _inputCtrl.clear();
    final userMsg = ChatMessage(role: MessageRole.user, content: text);
    setState(() {
      _messages.add(userMsg);
      _loading = true;
      _streamingContent = '';
    });
    _scrollToBottom();

    // Build history including optional system prompt.
    final history = <ChatMessage>[];
    if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
      history.add(ChatMessage(
          role: MessageRole.system, content: _systemPrompt!));
    }
    history.addAll(_messages);

    _streamSub = _api
        .chatCompletionStream(messages: history)
        .listen(
          (token) {
            if (!mounted) return;
            setState(
                () => _streamingContent = (_streamingContent ?? '') + token);
            _scrollToBottom();
          },
          onError: (Object e) {
            if (!mounted) return;
            final errMsg =
                e is ApiException ? e.message : e.toString();
            setState(() {
              _messages.add(ChatMessage(
                role: MessageRole.assistant,
                content: '⚠️ Error: $errMsg',
              ));
              _streamingContent = null;
              _loading = false;
            });
            _scrollToBottom();
          },
          onDone: () {
            if (!mounted) return;
            final content = _streamingContent;
            setState(() {
              if (content != null && content.isNotEmpty) {
                _messages.add(ChatMessage(
                  role: MessageRole.assistant,
                  content: content,
                ));
              }
              _streamingContent = null;
              _loading = false;
            });
            _scrollToBottom();
          },
          cancelOnError: true,
        );
  }

  /// Cancels an in-flight stream and commits whatever tokens arrived so far.
  void _stopStream() {
    _streamSub?.cancel();
    _streamSub = null;
    final content = _streamingContent;
    setState(() {
      if (content != null && content.isNotEmpty) {
        _messages.add(ChatMessage(
          role: MessageRole.assistant,
          content: content,
        ));
      }
      _streamingContent = null;
      _loading = false;
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() => setState(() => _messages.clear());

  void _showSystemPromptDialog() {
    final ctrl = TextEditingController(text: _systemPrompt ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('System Prompt'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Optional instruction for the model…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value =
                  ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
              setState(() => _systemPrompt = value);
              _saveSystemPrompt(value);
              Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ConnectionScreen()),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gemma 4 Chat'),
            Text(
              widget.config.baseUrl,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_systemPrompt != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: const Text('System'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'System prompt',
            onPressed: _showSystemPromptDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear chat',
            onPressed: _messages.isEmpty ? null : _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && _streamingContent == null
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    // +1 slot for the live streaming bubble (or typing indicator).
                    itemCount:
                        _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length && _loading) {
                        // Show tokens as they stream in; typing indicator before
                        // the first token arrives.
                        if (_streamingContent != null &&
                            _streamingContent!.isNotEmpty) {
                          return MessageBubble(
                            message: ChatMessage(
                              role: MessageRole.assistant,
                              content: _streamingContent!,
                            ),
                          );
                        }
                        return const _TypingIndicator();
                      }
                      return MessageBubble(message: _messages[i]);
                    },
                  ),
          ),
          _InputBar(
            controller: _inputCtrl,
            loading: _loading,
            onSend: _send,
            onStop: _stopStream,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 72, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('Start a conversation',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Messages are sent to the on-device Gemma 4 model.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.loading,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            onPressed: loading ? onStop : onSend,
            elevation: 0,
            backgroundColor:
                loading ? theme.colorScheme.error : null,
            foregroundColor:
                loading ? theme.colorScheme.onError : null,
            child: loading
                ? const Icon(Icons.stop_rounded)
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const SizedBox(
              width: 40,
              child: LinearProgressIndicator(),
            ),
          ),
        ],
      ),
    );
  }
}
