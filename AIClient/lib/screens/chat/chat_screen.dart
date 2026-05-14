import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';
import '../../models/server_config.dart';
import '../../services/api_service.dart';
import '../../services/server_launcher.dart';
import '../../tools/agent_loop.dart';
import '../../tools/hardware_tools.dart';
import '../../tools/tool_definition.dart';
import '../../widgets/message_bubble.dart';
import '../connection/connection_screen.dart';
import '../models/model_catalog_screen.dart';

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
  String? _systemPrompt;

  /// Tracks the model ID that is currently active in ApiService.instance.
  /// Starts from widget.config.modelId but may be updated when the user
  /// swaps models from the catalog screen — widget.config is immutable.
  late String _currentModelId;

  /// Accumulates tokens while a streaming response is in flight.
  /// Null when no stream is active; empty string before the first token arrives.
  String? _streamingContent;
  StreamSubscription<String>? _streamSub;

  static const _kSystemPromptKey = 'system_prompt';
  static const _kMessagesKey = 'chat_messages';

  /// Maximum number of messages (user + assistant) sent to the server.
  /// Older messages beyond this limit are shown in the UI but excluded from
  /// the request, keeping the context window manageable.
  static const _kMaxHistoryMessages = 20;

  @override
  void initState() {
    super.initState();
    _currentModelId = widget.config.modelId;
    _loadSystemPrompt();
    _loadMessages();
    registerHardwareTools();
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

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMessagesKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final messages = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      // FIX: clear before adding to prevent duplicates on hot reload /
      // widget rebuild (initState can be called more than once).
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });
      _scrollToBottom();
    } catch (_) {
      // Corrupted data — start fresh (existing key will be overwritten on next
      // save, so no manual cleanup needed).
    }
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kMessagesKey,
      jsonEncode(_messages.map((m) => m.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Sending & agent loop ──────────────────────────────────────────────────

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
    _saveMessages();
    _scrollToBottom();

    _runAgentTurn(_buildHistory(), 0);
  }

  /// Builds the message list to send to the server:
  /// tool system prompt + user system prompt + windowed conversation.
  /// Tool UI messages (role: tool) are excluded — only user/assistant turns.
  List<ChatMessage> _buildHistory() {
    final toolBlock = ToolRegistry.buildSystemPromptBlock();
    final userPrompt = (_systemPrompt ?? '').trim();
    final combined =
        [toolBlock, userPrompt].where((s) => s.isNotEmpty).join('\n\n');

    final history = <ChatMessage>[];
    if (combined.isNotEmpty) {
      history.add(ChatMessage(role: MessageRole.system, content: combined));
    }

    // Only pass user/assistant turns — tool UI messages stay in the visual list.
    final conversational = _messages
        .where((m) => m.role == MessageRole.user || m.role == MessageRole.assistant)
        .toList();
    final window = conversational.length > _kMaxHistoryMessages
        ? conversational.sublist(conversational.length - _kMaxHistoryMessages)
        : conversational;
    history.addAll(window);
    return history;
  }

  /// Streams one LLM turn. On completion calls [_handleAgentResponse].
  void _runAgentTurn(List<ChatMessage> history, int iteration) {
    setState(() => _streamingContent = '');

    _streamSub = ApiService.instance
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
            final msg = e is ApiException ? e.message : e.toString();
            setState(() {
              _messages.add(ChatMessage(
                  role: MessageRole.assistant,
                  content: '⚠️ Error: $msg'));
              _streamingContent = null;
              _loading = false;
            });
            _saveMessages();
            _scrollToBottom();
          },
          onDone: () {
            if (!mounted) return;
            final response = _streamingContent ?? '';
            setState(() => _streamingContent = null);
            _handleAgentResponse(response, history, iteration);
          },
          cancelOnError: true,
        );
  }

  /// Called after each LLM turn completes.
  /// Checks for a tool call; if found executes it and loops; otherwise finalises.
  Future<void> _handleAgentResponse(
      String response, List<ChatMessage> history, int iteration) async {
    final toolCall = AgentLoop.parseToolCall(response);

    // ── No tool call — finalise ──────────────────────────────────────────────
    if (toolCall == null || iteration >= AgentLoop.maxIterations) {
      final text = response.trim();
      if (text.isNotEmpty) {
        setState(() => _messages.add(
            ChatMessage(role: MessageRole.assistant, content: text)));
      }
      setState(() => _loading = false);
      _saveMessages();
      _scrollToBottom();
      return;
    }

    // ── Tool call found ───────────────────────────────────────────────────────
    // Show any text that came before the tool call marker.
    if (toolCall.textBefore.isNotEmpty) {
      setState(() => _messages.add(ChatMessage(
          role: MessageRole.assistant, content: toolCall.textBefore)));
    }

    final tool = ToolRegistry.find(toolCall.toolName);
    if (tool == null) {
      // Unknown tool — inject error result and loop.
      final errResult = 'Error: unknown tool "${toolCall.toolName}".';
      _injectToolResultAndLoop(
          toolCall.toolName, errResult, history, iteration);
      return;
    }

    // Show "tool running" indicator in the chat.
    setState(() => _messages.add(ChatMessage(
        role: MessageRole.tool,
        content: 'Running ${toolCall.toolName}…',
        toolName: toolCall.toolName)));
    _scrollToBottom();

    // Confirmation dialog for sensitive tools (e.g. send_sms).
    if (tool.requiresConfirmation && mounted) {
      final confirmed =
          await _showToolConfirmDialog(toolCall.toolName, toolCall.args);
      if (!confirmed) {
        setState(() {
          // Replace the "running…" indicator with "cancelled".
          _messages.last = ChatMessage(
              role: MessageRole.tool,
              content: 'Cancelled.',
              toolName: toolCall.toolName);
          _loading = false;
        });
        _saveMessages();
        return;
      }
    }

    // Execute.
    final result = await tool.execute(toolCall.args);

    // Update indicator → result.
    setState(() {
      _messages.last = ChatMessage(
          role: MessageRole.tool,
          content: result,
          toolName: toolCall.toolName);
    });
    _scrollToBottom();

    _injectToolResultAndLoop(toolCall.toolName, result, history, iteration);
  }

  void _injectToolResultAndLoop(
      String toolName, String result, List<ChatMessage> history, int iteration) {
    history.add(AgentLoop.toolResultMessage(toolName, result));
    _runAgentTurn(history, iteration + 1);
  }

  /// Confirmation dialog shown before executing tools with [requiresConfirmation].
  Future<bool> _showToolConfirmDialog(
      String toolName, Map<String, dynamic> args) async {
    if (!mounted) return false;

    final lines = args.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              const Icon(Icons.build_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Run: $toolName'),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The assistant wants to execute this tool:'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    lines,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Allow'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Cancels an in-flight stream and commits whatever tokens arrived so far.
  /// Also stops any pending agent loop iteration.
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
    _saveMessages();
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

  void _clearChat() {
    setState(() => _messages.clear());
    _saveMessages(); // overwrites with empty list
  }

  /// Opens the model catalog. If the user loads a different model, updates
  /// [_currentModelId] and re-configures the singleton for subsequent messages.
  Future<void> _openModelCatalog() async {
    final newModelId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ModelCatalogScreen()),
    );
    if (!mounted) return;
    // FIX: compare against _currentModelId (not widget.config.modelId which
    // is the original immutable value from construction time and becomes stale
    // after the first model swap).
    if (newModelId != null && newModelId != _currentModelId) {
      setState(() => _currentModelId = newModelId);
      ApiService.configure(widget.config.copyWith(modelId: newModelId));
    }
  }

  Future<void> _showSystemPromptDialog() async {
    // FIX: use a dedicated StatefulWidget so TextEditingController is
    // properly disposed when the dialog closes.
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _SystemPromptDialog(initialValue: _systemPrompt ?? ''),
    );
    if (!mounted) return;
    // result == null  → user cancelled (no change)
    // result == ''    → user cleared the prompt
    // result == '...' → user set a new prompt
    if (result != null) {
      final value = result.isEmpty ? null : result;
      setState(() => _systemPrompt = value);
      _saveSystemPrompt(value);
    }
  }

  // ── Stop server ─────────────────────────────────────────────────────────────

  /// Shows a confirmation dialog then:
  ///   1. HTTP POST /v1/models/unload  (frees native model memory)
  ///   2. Platform stop signal         (terminates the server process)
  ///   3. Navigates back to ConnectionScreen
  Future<void> _confirmStopServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Server?'),
        content: const Text(
          'This will unload the model and shut down the server.\n\n'
          'All model memory will be freed to the OS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop Server'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Cancel any in-flight inference stream first.
    _stopStream();

    // Step 1: unload model (best-effort, 5 s timeout).
    try {
      await ApiService.instance
          .unloadModel()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Server may be unreachable — proceed with platform stop anyway.
    }

    // Step 2: send platform stop signal.
    try {
      await ServerLauncher.stop();
    } catch (_) {
      // Ignore — don't block navigation on launcher errors.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server stopped — model memory freed.')),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
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
            icon: const Icon(Icons.model_training_outlined),
            tooltip: 'Manage models',
            onPressed: _openModelCatalog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear chat',
            onPressed: _messages.isEmpty ? null : _clearChat,
          ),
          PopupMenuButton<_ChatMenuAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (action) {
              switch (action) {
                case _ChatMenuAction.stopServer:
                  _confirmStopServer();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _ChatMenuAction.stopServer,
                child: Row(
                  children: [
                    Icon(Icons.stop_circle_outlined,
                        color: Theme.of(context).colorScheme.error,
                        size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Stop Server',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
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
                    itemCount: _messages.length + (_loading ? 1 : 0),
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
                      // Show a divider at the start of the context window so
                      // the user knows which messages are actually sent.
                      final windowStart = _messages.length > _kMaxHistoryMessages
                          ? _messages.length - _kMaxHistoryMessages
                          : 0;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i == windowStart && windowStart > 0)
                            _ContextWindowDivider(
                                excluded: windowStart),
                          MessageBubble(message: _messages[i]),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: _InputBar(
              controller: _inputCtrl,
              loading: _loading,
              onSend: _send,
              onStop: _stopStream,
            ),
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

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _ChatMenuAction { stopServer }

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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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

/// Shown once in the list at the point where older messages fall outside the
/// context window and will not be sent to the model.
class _ContextWindowDivider extends StatelessWidget {
  const _ContextWindowDivider({required this.excluded});

  /// Number of messages above this divider that are excluded from context.
  final int excluded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          const SizedBox(width: 8),
          Icon(Icons.history_toggle_off_outlined,
              size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            '$excluded message${excluded == 1 ? '' : 's'} outside context window',
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

// ── System prompt dialog ──────────────────────────────────────────────────────

/// Dedicated StatefulWidget so [TextEditingController] is always disposed
/// when the dialog is dismissed — avoids the leak from inline creation.
///
/// Returns:
/// - `null`  if the user cancelled (no change should be applied)
/// - `''`    if the user cleared the prompt
/// - `'...'` if the user entered text
class _SystemPromptDialog extends StatefulWidget {
  const _SystemPromptDialog({required this.initialValue});
  final String initialValue;

  @override
  State<_SystemPromptDialog> createState() => _SystemPromptDialogState();
}

class _SystemPromptDialogState extends State<_SystemPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('System Prompt'),
      content: TextField(
        controller: _ctrl,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: 'Optional instruction for the model…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // null → no change
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Set'),
        ),
      ],
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
