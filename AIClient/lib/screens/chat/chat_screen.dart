import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';
import '../../models/server_config.dart';
import '../../services/api_service.dart';
import '../../services/device_context_service.dart';
import '../../services/location_service.dart';
import '../../services/memory_service.dart';
import '../../services/server_launcher.dart';
import '../../services/weather_service.dart';
import '../../tools/agent_loop.dart';
import '../../tools/hardware_tools.dart';
import '../../tools/python_command.dart';
import '../../tools/python_runner.dart';
import '../../tools/tool_definition.dart';
import '../../tools/tool_result.dart';
import '../../widgets/message_bubble.dart';
import '../chart/chart_screen.dart';
import '../connection/connection_screen.dart';
import '../models/model_catalog_screen.dart';
import '../test/test_screen.dart';
import '../test/features_test_screen.dart';

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

  /// Cached device context (date/time, battery, network) + weather + memories.
  /// Refreshed once at startup; the model always sees current state.
  String _deviceContext = '';
  String? _weatherContext;
  String? _memoryContext;

  /// Image selected by the user but not yet sent.
  /// [_pendingImageBytes] drives the thumbnail preview in [_InputBar].
  /// [_pendingImageBase64] is attached to the outgoing [ChatMessage].
  Uint8List? _pendingImageBytes;
  String? _pendingImageBase64;

  /// Tracks the model ID that is currently active in ApiService.instance.
  /// Starts from widget.config.modelId but may be updated when the user
  /// swaps models from the catalog screen — widget.config is immutable.
  late String _currentModelId;

  /// Accumulates tokens while a streaming response is in flight.
  /// Null when no stream is active; empty string before the first token arrives.
  ///
  /// [_streamingContent] is the *display* version — memory tags are stripped
  /// out so they never appear in the live bubble.
  /// [_streamingRaw] is the unmodified version used for tag processing once
  /// the full response arrives.
  String? _streamingContent;
  String? _streamingRaw;
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
    PythonRunner.instance.initialize();
    _refreshContext(); // async — runs in background, no await
  }

  /// Fetches device context (date/time/battery/network), weather, and stored
  /// memories in parallel. Stores results in state so [_buildHistory] can
  /// inject them into every request.
  Future<void> _refreshContext() async {
    final results = await Future.wait([
      DeviceContextService.getContext(),
      _fetchWeather(),
      MemoryService.buildContextBlock(),
    ]);
    if (!mounted) return;
    setState(() {
      _deviceContext = results[0] as String;
      _weatherContext = results[1];
      _memoryContext = results[2];
    });
  }

  /// Refreshes only the memory context — called after memory tags are processed
  /// so the next message always sees the latest stored facts.
  Future<void> _refreshMemory() async {
    final memCtx = await MemoryService.buildContextBlock();
    if (!mounted) return;
    setState(() => _memoryContext = memCtx);
  }

  Future<String?> _fetchWeather() async {
    final location = await LocationService.getLocation();
    if (location == null) return null;
    return WeatherService.getWeather(location.latitude, location.longitude);
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

  static final _toolCmdRe = RegExp(
    r'^use tool\s+(.+)$',
    caseSensitive: false,
    dotAll: true,
  );

  void _send() {
    final text = _inputCtrl.text.trim();
    // Allow send when there is text, an image, or both.
    if ((text.isEmpty && _pendingImageBytes == null) || _loading) return;
    _inputCtrl.clear();

    // Snapshot and clear pending image before any async work.
    final imageBase64 = _pendingImageBase64;
    final hasImage = imageBase64 != null;

    // Command shortcuts only work for text-only messages.
    if (!hasImage) {
      if (text.toLowerCase() == 'list tools') {
        _handlePythonList();
        return;
      }
      final toolMatch = _toolCmdRe.firstMatch(text);
      if (toolMatch != null) {
        _handleToolCommand(text, toolMatch.group(1)!.trim());
        return;
      }
    }

    final userMsg = ChatMessage(
      role: MessageRole.user,
      content: text,
      attachedImageBase64: imageBase64,
    );
    setState(() {
      _messages.add(userMsg);
      _loading = true;
      _streamingContent = '';
      _pendingImageBytes = null;
      _pendingImageBase64 = null;
    });
    _saveMessages();
    _scrollToBottom();

    _runAgentTurn(_buildHistory(), 0);
  }

  void _handlePythonList() {
    // Guard against double-submit (rapid tap while list is rendering).
    if (_loading) return;
    setState(() {
      _messages.add(ChatMessage(role: MessageRole.user, content: 'list tools'));
      _messages.add(ChatMessage(
        role: MessageRole.tool,
        content: PythonCommand.listMessage(),
        toolName: ToolNames.pythonLibs,
      ));
    });
    _saveMessages();
    _scrollToBottom();
  }

  /// Handles the `use tool <request>` command.
  ///
  /// [_loading] stays `true` for the ENTIRE duration so the stop button is
  /// always visible. [_stopStream] cancels both the LLM stream (via [_streamSub])
  /// and any in-flight Python execution (via [PythonRunner.cancel]).
  ///
  /// A top-level try-finally guarantees [_loading] is always reset on exit,
  /// even on unexpected exceptions.
  Future<void> _handleToolCommand(String rawInput, String request) async {
    setState(() {
      _messages.add(ChatMessage(role: MessageRole.user, content: rawInput));
      _loading = true;
      _messages.add(ChatMessage(
        role: MessageRole.tool,
        content: 'Generating code…',
        toolName: ToolNames.pythonLibs,
      ));
    });
    final chipIndex = _messages.length - 1;
    _scrollToBottom();

    void updateChip(String content, {bool isError = false}) {
      if (!mounted) return;
      setState(() {
        _messages[chipIndex] = ChatMessage(
          role: MessageRole.tool,
          content: content,
          toolName: isError ? ToolNames.pythonError : ToolNames.pythonLibs,
        );
      });
    }

    try {
      // ── Location fetch (concurrent with LLM — no added latency) ───────────
      // Fires in the background while the model generates code. Result is
      // awaited just before execution and injected as Python preamble variables
      // (user_latitude / user_longitude) if the device granted permission.
      final locationFuture = LocationService.getLocation();

      // ── Phase 1: LLM code generation ──────────────────────────────────────
      // Use _streamSub so _stopStream() can cancel this stream too.
      final llmResponseBuf = StringBuffer();
      final streamDone = Completer<void>();

      _streamSub = ApiService.instance
          .chatCompletionStream(messages: [
            ChatMessage(
                role: MessageRole.user,
                content: PythonCommand.buildToolPrompt(request)),
          ])
          .listen(
            (token) {
              llmResponseBuf.write(token);
            },
            onError: (Object e) {
              if (!streamDone.isCompleted) streamDone.completeError(e);
            },
            onDone: () {
              if (!streamDone.isCompleted) streamDone.complete();
            },
            cancelOnError: true,
          );

      try {
        await streamDone.future;
      } catch (e) {
        if (!mounted || !_loading) return; // cancelled or unmounted
        updateChip('Code generation error: $e', isError: true);
        return;
      }

      // Check if user cancelled while streaming.
      if (!mounted || !_loading) return;

      // ── Phase 2: Code extraction ───────────────────────────────────────────
      final code = PythonCommand.extractCode(llmResponseBuf.toString());
      if (code == null || code.trim().isEmpty) {
        updateChip('Could not extract Python code from response.',
            isError: true);
        return;
      }

      // ── Phase 3: Python execution ──────────────────────────────────────────
      updateChip('Running tool…');

      // Prepend GPS variables if the device granted location permission.
      // user_latitude / user_longitude are available to every generated script;
      // the model uses them when the task involves location.
      final location = await locationFuture;
      final codeToRun =
          location != null ? '${location.pythonPreamble}$code' : code;

      final result = await PythonRunner.instance.execute(
        codeToRun,
        onProgress: (status) => updateChip(status),
      );

      if (!mounted || !_loading) {
        // User cancelled while Python was running — mark chip stopped.
        updateChip('Stopped.');
        return;
      }

      setState(() =>
          _messages[chipIndex] = AgentLoop.displayMessage('tool', result));
    } catch (e) {
      // Unexpected exception — show error in chip rather than silently hanging.
      if (mounted) updateChip('Unexpected error: $e', isError: true);
    } finally {
      // Guaranteed reset — _loading can never be left stuck true.
      if (mounted) {
        setState(() {
          _streamingContent = null;
          _loading = false;
        });
      }
      _saveMessages();
      _scrollToBottom();
    }
  }

  /// Assembles the auto-injected context block prepended to every system prompt:
  /// current date/time, battery, network connectivity, weather, stored memories,
  /// and the persistent memory instructions the model uses to save/forget facts.
  String _buildContextBlock() {
    final parts = <String>[];

    if (_deviceContext.isNotEmpty) {
      parts.add('[Device Context]\n$_deviceContext');
      if (_weatherContext != null) {
        parts.add('[Current Weather]\n$_weatherContext');
      }
    }

    if (_memoryContext != null) {
      parts.add(_memoryContext!);
    }

    // Always include memory instructions so the model knows how to use them
    // even before any facts have been stored.
    parts.add(MemoryService.memoryInstructions);

    return parts.join('\n\n');
  }

  /// Builds the message list to send to the server:
  /// context block + tool system prompt + user system prompt + windowed conversation.
  /// Tool UI messages (role: tool) are excluded — only user/assistant turns.
  List<ChatMessage> _buildHistory() {
    final contextBlock = _buildContextBlock();
    final toolBlock = ToolRegistry.buildSystemPromptBlock();
    final userPrompt = (_systemPrompt ?? '').trim();
    final combined =
        [contextBlock, toolBlock, userPrompt].where((s) => s.isNotEmpty).join('\n\n');

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
  ///
  /// Memory tags emitted by the model are stripped from [_streamingContent]
  /// (the live display buffer) so they never flash on screen.  The raw,
  /// unmodified text is kept in [_streamingRaw] and forwarded to
  /// [_handleAgentResponse] so [MemoryService.processTags] can persist them.
  void _runAgentTurn(List<ChatMessage> history, int iteration) {
    setState(() {
      _streamingContent = '';
      _streamingRaw = '';
    });

    _streamSub = ApiService.instance
        .chatCompletionStream(messages: history)
        .listen(
          (token) {
            if (!mounted) return;
            final newRaw = (_streamingRaw ?? '') + token;
            setState(() {
              _streamingRaw = newRaw;
              _streamingContent = MemoryService.stripTags(newRaw);
            });
            _scrollToBottom();
          },
          onError: (Object e) {
            if (!mounted) return;
            final msg = e is ApiException ? e.message : e.toString();

            // If the request contained an image and the server rejected it,
            // strip images from history and retry as text-only. The current
            // Gemma 4 .litertlm exports are text-only — vision support requires
            // a model export that includes the SigLIP visual encoder.
            final hasImages = history.any((m) => m.attachedImageBase64 != null);
            if (hasImages) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Current model doesn\'t support images — sending text only.',
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
              final textOnly = history
                  .map((m) => m.attachedImageBase64 != null
                      ? ChatMessage(
                          role: m.role,
                          content: m.content,
                          toolName: m.toolName,
                          timestamp: m.timestamp,
                        )
                      : m)
                  .toList();
              _streamSub?.cancel();
              _streamSub = null;
              setState(() {
                _streamingContent = '';
                _streamingRaw = '';
              });
              _runAgentTurn(textOnly, iteration);
              return;
            }

            setState(() {
              _messages.add(ChatMessage(
                  role: MessageRole.assistant,
                  content: '⚠️ Error: $msg'));
              _streamingContent = null;
              _streamingRaw = null;
              _loading = false;
            });
            _saveMessages();
            _scrollToBottom();
          },
          onDone: () {
            if (!mounted) return;
            // Use raw content so processTags can find and commit any memory tags.
            final response = _streamingRaw ?? '';
            setState(() {
              _streamingContent = null;
              _streamingRaw = null;
            });
            _handleAgentResponse(response, history, iteration);
          },
          cancelOnError: true,
        );
  }

  /// Called after each LLM turn completes.
  /// Checks for a tool call; if found executes it and loops; otherwise finalises.
  /// Wrapped in try-catch so any unexpected exception always resets [_loading].
  Future<void> _handleAgentResponse(
      String response, List<ChatMessage> history, int iteration) async {
    try {
      await _handleAgentResponseInner(response, history, iteration);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
            role: MessageRole.assistant, content: '⚠️ Unexpected error: $e'));
        _loading = false;
      });
      _saveMessages();
      _scrollToBottom();
    }
  }

  Future<void> _handleAgentResponseInner(
      String response, List<ChatMessage> history, int iteration) async {
    final toolCall = AgentLoop.parseToolCall(response);

    // ── No tool call — finalise ──────────────────────────────────────────────
    if (toolCall == null || iteration >= AgentLoop.maxIterations) {
      // Process any memory store/forget tags the model emitted.
      // processTags returns the cleaned text (tags removed) if any were found,
      // or null if the response contained no memory tags.
      final cleaned = await MemoryService.processTags(response);
      if (!mounted) return;

      final text = (cleaned ?? response).trim();
      if (text.isNotEmpty) {
        setState(() => _messages.add(
            ChatMessage(role: MessageRole.assistant, content: text)));
      }

      // Refresh in-memory context so the next message sees the updated facts.
      if (cleaned != null) _refreshMemory();

      // DEBUG: if response contained a tool_call tag but we failed to parse it,
      // show a debug bubble with the raw bytes so we can diagnose the format.
      // TODO: remove before release.
      if (toolCall == null && AgentLoop.hasToolCall(response)) {
        final escaped = response
            .replaceAll('\n', '↵')
            .replaceAll('\r', '↵')
            .replaceAll('\t', '→');
        final preview = escaped.length > 600
            ? '${escaped.substring(0, 600)}[truncated]'
            : escaped;
        final logLines = AgentLoop.parseLog.join('\n');
        setState(() => _messages.add(ChatMessage(
              role: MessageRole.tool,
              content: '🐛 DEBUG\n\n── PARSE LOG ──\n$logLines\n\n── RAW RESPONSE (↵=newline) ──\n$preview',
              toolName: ToolNames.parserDebug,
            )));
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
      final errResult = TextToolResult('Error: unknown tool "${toolCall.toolName}".');
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

    // Execute — 60 s hard timeout so a misbehaving tool can never leave
    // _loading stuck true (the outer try-catch in _handleAgentResponse is the
    // final safety net if the tool throws instead of timing out).
    final ToolResult result;
    try {
      result = await tool.execute(toolCall.args).timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
            TextToolResult('Tool "${toolCall.toolName}" timed out (60 s).'),
      );
    } catch (e) {
      setState(() {
        _messages.last = ChatMessage(
            role: MessageRole.tool,
            content: 'Tool error: $e',
            toolName: toolCall.toolName);
        _loading = false;
      });
      _saveMessages();
      _scrollToBottom();
      return;
    }

    // Update indicator → result.
    setState(() {
      _messages.last = AgentLoop.displayMessage(toolCall.toolName, result);
    });
    _scrollToBottom();

    _injectToolResultAndLoop(toolCall.toolName, result, history, iteration);
  }

  void _injectToolResultAndLoop(
      String toolName, ToolResult result, List<ChatMessage> history, int iteration) {
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

  /// Cancels ALL in-flight work and returns the UI to the input-ready state.
  ///
  /// Covers every running phase:
  /// - LLM stream (via [_streamSub]) — works for both normal chat and
  ///   `_handleToolCommand`'s code-generation phase.
  /// - Python execution (via [PythonRunner.cancel]) — immediately resolves
  ///   any awaited [PythonRunner.execute] call.
  ///
  /// Setting [_loading] = false here acts as the cancellation signal that
  /// [_handleToolCommand] checks after each await to exit cleanly.
  void _stopStream() {
    _streamSub?.cancel();
    _streamSub = null;
    PythonRunner.instance.cancel();
    // _streamingContent is already tag-stripped — safe to persist as-is.
    final content = _streamingContent;
    setState(() {
      if (content != null && content.isNotEmpty) {
        _messages.add(ChatMessage(
          role: MessageRole.assistant,
          content: content,
        ));
      }
      _streamingContent = null;
      _streamingRaw = null;
      _loading = false;
    });
    _saveMessages();
  }

  // ── Image attachment ──────────────────────────────────────────────────────────

  /// Shows a bottom sheet to choose camera or gallery, then stores the picked
  /// image as [_pendingImageBytes] / [_pendingImageBase64] for the next send.
  Future<void> _pickImage() async {
    if (!mounted) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingImageBytes = bytes;
        _pendingImageBase64 = base64Encode(bytes);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick image: $e')),
      );
    }
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
                case _ChatMenuAction.runTests:
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TestScreen()),
                  );
                case _ChatMenuAction.runFeatureTests:
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const FeaturesTestScreen()),
                  );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ChatMenuAction.runTests,
                child: Row(
                  children: [
                    Icon(Icons.science_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Run Python Tests'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: _ChatMenuAction.runFeatureTests,
                child: Row(
                  children: [
                    Icon(Icons.checklist_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Run Feature Tests'),
                  ],
                ),
              ),
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
      body: Stack(
        children: [
          Column(
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
                              MessageBubble(
                                message: _messages[i],
                                onViewChart: _messages[i].htmlContent != null
                                    ? () => Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => ChartScreen(html: _messages[i].htmlContent!),
                                        ))
                                    : null,
                              ),
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
                  pendingImageBytes: _pendingImageBytes,
                  onPickImage: _pickImage,
                  onClearImage: () => setState(() {
                    _pendingImageBytes = null;
                    _pendingImageBase64 = null;
                  }),
                ),
              ),
            ],
          ),
          // Positioned keeps the WebView in the active render tree so Android
          // does not throttle its JavaScript execution (Offstage causes throttling).
          Positioned(
            left: 0, bottom: 0,
            width: 1, height: 1,
            child: PythonRunner.instance.widget,
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

enum _ChatMenuAction { stopServer, runTests, runFeatureTests }

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.loading,
    required this.onSend,
    required this.onStop,
    this.pendingImageBytes,
    this.onPickImage,
    this.onClearImage,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// Decoded bytes of the image queued for the next send, or null.
  final Uint8List? pendingImageBytes;

  /// Called when the user taps the attach button.
  final VoidCallback? onPickImage;

  /// Called when the user taps the × on the pending thumbnail.
  final VoidCallback? onClearImage;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Pending image thumbnail ──────────────────────────────────────
          if (pendingImageBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      pendingImageBytes!,
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                  // × dismiss button
                  GestureDetector(
                    onTap: onClearImage,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),

          // ── Text field row ───────────────────────────────────────────────
          Row(
            children: [
              // Attach image button (hidden while loading)
              if (!loading)
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded),
                  tooltip: 'Attach image',
                  visualDensity: VisualDensity.compact,
                  onPressed: onPickImage,
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: pendingImageBytes != null
                        ? 'Add a caption…'
                        : 'Message…',
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
