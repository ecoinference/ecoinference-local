import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/api_service.dart';
import '../../services/memory_service.dart';

// ── Test-key prefix ───────────────────────────────────────────────────────────
//
// All memory entries written by these tests use this prefix so they can be
// bulk-deleted without touching real user data.

const _kTestPrefix = '_autotest_';

// ── Category ──────────────────────────────────────────────────────────────────

enum _Category { memory, image }

// ── Test case ─────────────────────────────────────────────────────────────────

class _TestCase {
  const _TestCase({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.directFn,
    this.e2eSetup,
    this.e2eMessages,
    this.mustContain = const [],
    this.mustNotContain = const [],
  }) : assert(
          (directFn != null) != (e2eMessages != null),
          'Exactly one of directFn or e2eMessages must be supplied',
        );

  final String id;
  final String name;
  final String description;
  final _Category category;

  /// Direct test — synchronous logic; returns a display string on success,
  /// throws on failure.  No server or LLM required.
  final Future<String> Function()? directFn;

  /// E2E: optional async setup that runs before the LLM call (e.g. pre-store
  /// a memory entry or generate the test image).
  final Future<void> Function()? e2eSetup;

  /// E2E: builds the message list sent to [ApiService.chatCompletionStream].
  final Future<List<ChatMessage>> Function()? e2eMessages;

  /// Strings that must ALL appear in the result text.
  final List<String> mustContain;

  /// Strings that must NOT appear in the result text.
  final List<String> mustNotContain;

  bool get isE2E => e2eMessages != null;
}

// ── Test result (mutable) ─────────────────────────────────────────────────────

enum _Status { pending, running, passed, failed }

class _TestResult {
  _TestResult(this.testCase);
  final _TestCase testCase;
  _Status status = _Status.pending;
  String detail = '';
  Duration? elapsed;
}

// ── Test image ────────────────────────────────────────────────────────────────
//
// Generates a 64×64 four-colour grid (red / green / blue / yellow) on-device
// at test-run time.  Encoded as PNG — the server writes the bytes to a .jpg
// temp file, but the LiteRT-LM engine detects the actual format from magic
// bytes and handles it correctly.

Future<String> _makeTestImageBase64() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 64, 64));
  canvas.drawRect(const Rect.fromLTWH(0, 0, 32, 32),
      Paint()..color = const Color(0xFFFF0000)); // top-left  red
  canvas.drawRect(const Rect.fromLTWH(32, 0, 32, 32),
      Paint()..color = const Color(0xFF00CC00)); // top-right green
  canvas.drawRect(const Rect.fromLTWH(0, 32, 32, 32),
      Paint()..color = const Color(0xFF0000FF)); // bot-left  blue
  canvas.drawRect(const Rect.fromLTWH(32, 32, 32, 32),
      Paint()..color = const Color(0xFFFFCC00)); // bot-right yellow
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return base64Encode(bytes!.buffer.asUint8List());
}

// ── Test-memory helpers ───────────────────────────────────────────────────────

Future<String?> _readTestKey(String key) async =>
    (await MemoryService.listAll())['$_kTestPrefix$key'];

// ── Test registry ─────────────────────────────────────────────────────────────

List<_TestCase> _buildCases() => [

  // ── Memory: direct ──────────────────────────────────────────────────────

  _TestCase(
    id: 'mem_store_load',
    name: 'Memory — store & load',
    category: _Category.memory,
    description: 'store(key, val) then listAll()[key] == val',
    directFn: () async {
      await MemoryService.store('${_kTestPrefix}fruit', 'mango');
      final val = await _readTestKey('fruit');
      if (val != 'mango') throw Exception('Expected "mango", got "$val"');
      return 'Stored and retrieved: ${_kTestPrefix}fruit = "$val"';
    },
  ),

  _TestCase(
    id: 'mem_forget',
    name: 'Memory — forget',
    category: _Category.memory,
    description: 'store then forget → key absent from listAll()',
    directFn: () async {
      await MemoryService.store('${_kTestPrefix}animal', 'cat');
      await MemoryService.forget('${_kTestPrefix}animal');
      final val = await _readTestKey('animal');
      if (val != null) throw Exception('Key still present after forget()');
      return 'Key absent after forget() ✓';
    },
  ),

  _TestCase(
    id: 'mem_strip_store_tag',
    name: 'Memory — stripTags removes <mem_store>',
    category: _Category.memory,
    description: 'stripTags() strips tag without writing to prefs',
    directFn: () async {
      // Use a unique key to avoid colliding with earlier test runs.
      const key = '${_kTestPrefix}strip_store_colour';
      const input = 'Hello <mem_store key="$key" value="blue"/> world';
      final stripped = MemoryService.stripTags(input);
      if (stripped.contains('<mem_store')) {
        throw Exception('Tag not removed: "$stripped"');
      }
      if (!stripped.contains('Hello') || !stripped.contains('world')) {
        throw Exception('Surrounding text altered: "$stripped"');
      }
      // stripTags must NOT persist anything.
      final all = await MemoryService.listAll();
      if (all.containsKey(key)) {
        throw Exception('stripTags() must not write to prefs — "$key" found');
      }
      return 'Stripped: "$stripped"  (no prefs write ✓)';
    },
  ),

  _TestCase(
    id: 'mem_strip_forget_tag',
    name: 'Memory — stripTags removes <mem_forget>',
    category: _Category.memory,
    description: 'stripTags() strips forget tag, surrounding text intact',
    directFn: () async {
      const input = 'OK <mem_forget key="${_kTestPrefix}city"/> done';
      final stripped = MemoryService.stripTags(input);
      if (stripped.contains('<mem_forget')) {
        throw Exception('Tag not removed: "$stripped"');
      }
      if (!stripped.contains('OK') || !stripped.contains('done')) {
        throw Exception('Surrounding text altered: "$stripped"');
      }
      return 'Stripped: "$stripped"';
    },
  ),

  _TestCase(
    id: 'mem_process_store_tag',
    name: 'Memory — processTags() persists store tag',
    category: _Category.memory,
    description: '<mem_store> tag → value written to SharedPreferences',
    directFn: () async {
      const key = '${_kTestPrefix}colour';
      const text =
          'Sure! <mem_store key="$key" value="crimson"/> Got it.';
      final cleaned = await MemoryService.processTags(text);
      if (cleaned == null) throw Exception('processTags() returned null — tag not detected');
      if (cleaned.contains('<mem_store')) throw Exception('Tag not stripped from cleaned text');
      final stored = await _readTestKey('colour');
      if (stored != 'crimson') throw Exception('Expected "crimson", got "$stored"');
      return 'Cleaned: "$cleaned"\n'
          'Stored: $key = "$stored"';
    },
  ),

  _TestCase(
    id: 'mem_process_forget_tag',
    name: 'Memory — processTags() removes forget tag',
    category: _Category.memory,
    description: '<mem_forget> tag → key deleted from SharedPreferences',
    directFn: () async {
      const key = '${_kTestPrefix}city';
      await MemoryService.store(key, 'Denver');
      const text = 'Forgotten. <mem_forget key="$key"/>';
      final cleaned = await MemoryService.processTags(text);
      if (cleaned == null) throw Exception('processTags() returned null');
      final val = await _readTestKey('city');
      if (val != null) throw Exception('Key still present after forget tag');
      return 'Cleaned: "$cleaned"\n$key removed ✓';
    },
  ),

  _TestCase(
    id: 'mem_context_block',
    name: 'Memory — buildContextBlock()',
    category: _Category.memory,
    description: 'Stored entries appear in context block under [Memories]',
    directFn: () async {
      await MemoryService.store('${_kTestPrefix}pet', 'hamster');
      await MemoryService.store('${_kTestPrefix}sport', 'cycling');
      final block = await MemoryService.buildContextBlock();
      if (block == null) throw Exception('buildContextBlock() returned null');
      if (!block.contains('[Memories]')) throw Exception('"[Memories]" header missing');
      if (!block.contains('hamster')) throw Exception('"hamster" missing from block');
      if (!block.contains('cycling')) throw Exception('"cycling" missing from block');
      return block;
    },
  ),

  // ── Memory: E2E ─────────────────────────────────────────────────────────

  _TestCase(
    id: 'mem_e2e_store',
    name: 'E2E — LLM writes a memory tag',
    category: _Category.memory,
    description: 'Ask LLM to remember a fact → raw response contains <mem_store>',
    mustContain: ['mem_store'],
    e2eMessages: () async => [
      ChatMessage(
        role: MessageRole.system,
        content: MemoryService.memoryInstructions,
      ),
      ChatMessage(
        role: MessageRole.user,
        content:
            'My lucky number is 77. Please remember this for future conversations.',
      ),
    ],
  ),

  _TestCase(
    id: 'mem_e2e_recall',
    name: 'E2E — LLM recalls a stored memory',
    category: _Category.memory,
    description: 'Pre-store a fact → LLM answers from the context block',
    mustContain: ['pineapple'],
    e2eSetup: () async =>
        MemoryService.store('${_kTestPrefix}favourite_fruit', 'pineapple'),
    e2eMessages: () async {
      final block = await MemoryService.buildContextBlock();
      final system = [
        if (block != null) block,
        MemoryService.memoryInstructions,
      ].join('\n\n');
      return [
        ChatMessage(role: MessageRole.system, content: system),
        ChatMessage(
          role: MessageRole.user,
          content: 'What is my favourite fruit?',
        ),
      ];
    },
  ),

  // ── Image: direct ────────────────────────────────────────────────────────

  _TestCase(
    id: 'img_json_text_only',
    name: 'Image — text-only JSON format',
    category: _Category.image,
    description: 'No image → toApiJson() content is a plain String',
    directFn: () async {
      final msg = ChatMessage(role: MessageRole.user, content: 'hello');
      final json = msg.toApiJson();
      final content = json['content'];
      if (content is! String) {
        throw Exception('Expected String, got ${content.runtimeType}');
      }
      if (content != 'hello') throw Exception('Wrong value: "$content"');
      return 'content = "$content"  (String ✓)';
    },
  ),

  _TestCase(
    id: 'img_json_multimodal',
    name: 'Image — multimodal JSON structure',
    category: _Category.image,
    description: 'With image → content is [text, image_url] array',
    directFn: () async {
      final msg = ChatMessage(
        role: MessageRole.user,
        content: 'What is this?',
        attachedImageBase64: 'abc123test',
      );
      final json = msg.toApiJson();
      final content = json['content'];
      if (content is! List) {
        throw Exception('Expected List, got ${content.runtimeType}');
      }
      if (content.length != 2) {
        throw Exception('Expected 2 parts, got ${content.length}');
      }
      final text = content[0] as Map<String, dynamic>;
      final img = content[1] as Map<String, dynamic>;
      if (text['type'] != 'text') throw Exception('Part 0 type is "${text['type']}"');
      if (text['text'] != 'What is this?') throw Exception('Text part mismatch');
      if (img['type'] != 'image_url') throw Exception('Part 1 type is "${img['type']}"');
      final url = (img['image_url'] as Map)['url'] as String;
      if (!url.startsWith('data:image/jpeg;base64,')) {
        throw Exception('Unexpected URL prefix: "${url.substring(0, 30)}"');
      }
      if (!url.endsWith('abc123test')) throw Exception('Payload not at end of URL');
      return 'text="${text['text']}"  url="${url.substring(0, 32)}…"  ✓';
    },
  ),

  _TestCase(
    id: 'img_json_empty_caption',
    name: 'Image — empty caption uses space placeholder',
    category: _Category.image,
    description: 'Empty text + image → text part is " " (server rejects empty)',
    directFn: () async {
      final msg = ChatMessage(
        role: MessageRole.user,
        content: '',
        attachedImageBase64: 'xyz',
      );
      final json = msg.toApiJson();
      final content = json['content'] as List;
      final textPart = content[0] as Map<String, dynamic>;
      final text = textPart['text'] as String;
      if (text.isEmpty) {
        throw Exception('text part is empty — the server will reject this request');
      }
      return 'text part = "${text.trim().isEmpty ? "<single space>" : '"$text"'}"  ✓';
    },
  ),

  _TestCase(
    id: 'img_json_tool_role_coerced',
    name: 'Image — tool role → user in JSON',
    category: _Category.image,
    description: 'MessageRole.tool serialises as role="user" (Gemma has no tool role)',
    directFn: () async {
      final msg = ChatMessage(
        role: MessageRole.tool,
        content: '[Tool result: 42]',
        toolName: 'calculator',
      );
      final json = msg.toApiJson();
      if (json['role'] != 'user') {
        throw Exception('role="${json['role']}" — expected "user"');
      }
      return 'role="user" ✓  content="${json['content']}"';
    },
  ),

  // ── Image: E2E ───────────────────────────────────────────────────────────

  _TestCase(
    id: 'img_e2e_vision',
    name: 'E2E — vision: describe 4-colour test image',
    category: _Category.image,
    description:
        'Send a red/green/blue/yellow grid → LLM returns non-empty description',
    mustNotContain: ['[ERROR:'],
    e2eMessages: () async {
      final b64 = await _makeTestImageBase64();
      return [
        ChatMessage(
          role: MessageRole.user,
          content: 'Describe what you see in this image in one sentence.',
          attachedImageBase64: b64,
        ),
      ];
    },
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class FeaturesTestScreen extends StatefulWidget {
  const FeaturesTestScreen({super.key});

  @override
  State<FeaturesTestScreen> createState() => _FeaturesTestScreenState();
}

class _FeaturesTestScreenState extends State<FeaturesTestScreen> {
  late final List<_TestResult> _results =
      _buildCases().map(_TestResult.new).toList();

  bool _running = false;
  int _current = -1;

  int get _passed => _results.where((r) => r.status == _Status.passed).length;
  int get _failed => _results.where((r) => r.status == _Status.failed).length;

  // ── Run all ───────────────────────────────────────────────────────────────

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _current = 0;
      for (final r in _results) {
        r.status = _Status.pending;
        r.detail = '';
        r.elapsed = null;
      }
    });

    await _cleanupTestMemories(); // start clean

    for (int i = 0; i < _results.length; i++) {
      if (!mounted) break;
      setState(() => _current = i);
      await _runOne(_results[i]);
      if (mounted) setState(() {});
    }

    await _cleanupTestMemories(); // leave no test artefacts behind

    if (mounted) setState(() { _running = false; _current = -1; });
  }

  Future<void> _cleanupTestMemories() async {
    final all = await MemoryService.listAll();
    for (final key in all.keys) {
      if (key.startsWith(_kTestPrefix)) await MemoryService.forget(key);
    }
  }

  // ── Run one ───────────────────────────────────────────────────────────────

  Future<void> _runOne(_TestResult r) async {
    r.status = _Status.running;
    if (mounted) setState(() {});

    final sw = Stopwatch()..start();
    try {
      final detail = r.testCase.isE2E
          ? await _runE2E(r.testCase)
          : await r.testCase.directFn!();
      sw.stop();
      r.elapsed = sw.elapsed;
      _evaluate(r, detail);
    } catch (e) {
      sw.stop();
      r.elapsed = sw.elapsed;
      r.status = _Status.failed;
      r.detail = 'Exception: $e';
    }
  }

  // ── E2E runner ────────────────────────────────────────────────────────────

  Future<String> _runE2E(_TestCase tc) async {
    if (!ApiService.isConfigured) {
      throw Exception('ApiService not configured — connect to AIServer first');
    }
    if (tc.e2eSetup != null) await tc.e2eSetup!();

    final messages = await tc.e2eMessages!();
    final buf = StringBuffer();
    final done = Completer<void>();

    ApiService.instance
        .chatCompletionStream(messages: messages, maxTokens: 256)
        .listen(
          buf.write,
          onError: (Object e) { if (!done.isCompleted) done.completeError(e); },
          onDone: ()          { if (!done.isCompleted) done.complete(); },
          cancelOnError: true,
        );

    await done.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw TimeoutException('No response within 90 s'),
    );

    final raw = buf.toString().trim();
    if (raw.isEmpty) throw Exception('Server returned an empty response');
    return raw;
  }

  // ── Evaluate ──────────────────────────────────────────────────────────────

  void _evaluate(_TestResult r, String content) {
    for (final kw in r.testCase.mustContain) {
      if (!content.contains(kw)) {
        r.status = _Status.failed;
        r.detail = 'Expected "$kw" not found in:\n$content';
        return;
      }
    }
    for (final kw in r.testCase.mustNotContain) {
      if (content.contains(kw)) {
        r.status = _Status.failed;
        r.detail = 'Unexpected "$kw" found in:\n$content';
        return;
      }
    }
    r.status = _Status.passed;
    r.detail = content.length > 300
        ? '${content.substring(0, 300)}…'
        : content;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature Tests'),
        actions: [
          if (_running)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Run all tests',
              onPressed: _runAll,
            ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(
            passed: _passed,
            failed: _failed,
            total: _results.length,
            serverReady: ApiService.isConfigured,
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                return _TestTile(
                  key: ValueKey(r.testCase.id),
                  result: r,
                  isRunning: _running && _current == i,
                  theme: theme,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.passed,
    required this.failed,
    required this.total,
    required this.serverReady,
  });

  final int passed, failed, total;
  final bool serverReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _Badge('$passed passed', Colors.green),
          const SizedBox(width: 8),
          _Badge('$failed failed', failed > 0 ? Colors.red : Colors.grey),
          const SizedBox(width: 8),
          Text('of $total', style: theme.textTheme.bodySmall),
          const Spacer(),
          if (!serverReady)
            Chip(
              label: const Text('No server'),
              avatar: const Icon(Icons.wifi_off_outlined, size: 14),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.errorContainer,
              labelStyle: TextStyle(color: theme.colorScheme.onErrorContainer),
            )
          else
            Chip(
              label: const Text('Server connected'),
              avatar: const Icon(Icons.wifi_outlined, size: 14),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.tertiaryContainer,
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ── Test tile ─────────────────────────────────────────────────────────────────

class _TestTile extends StatelessWidget {
  const _TestTile({
    super.key,
    required this.result,
    required this.isRunning,
    required this.theme,
  });

  final _TestResult result;
  final bool isRunning;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final tc = r.testCase;

    final (IconData icon, Color color) = switch (r.status) {
      _Status.pending => (Icons.radio_button_unchecked, Colors.grey),
      _Status.running => (Icons.hourglass_top_outlined, theme.colorScheme.primary),
      _Status.passed  => (Icons.check_circle_outline, Colors.green),
      _Status.failed  => (Icons.cancel_outlined, Colors.red),
    };

    final subtitle = r.elapsed != null
        ? '${tc.description}  ·  ${r.elapsed!.inMilliseconds} ms'
        : tc.description;

    // Category chip colours
    final (Color catBg, Color catFg, String catLabel) =
        tc.category == _Category.memory
            ? (
                theme.colorScheme.primaryContainer,
                theme.colorScheme.onPrimaryContainer,
                'Memory',
              )
            : (
                theme.colorScheme.tertiaryContainer,
                theme.colorScheme.onTertiaryContainer,
                'Image',
              );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ExpansionTile(
        leading: isRunning
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.colorScheme.primary),
              )
            : Icon(icon, color: color, size: 20),
        title: Row(
          children: [
            // Category badge
            _Chip(label: catLabel, bg: catBg, fg: catFg),
            const SizedBox(width: 6),
            // E2E badge
            if (tc.isE2E) ...[
              _Chip(
                label: 'E2E',
                bg: theme.colorScheme.secondaryContainer,
                fg: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                tc.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: r.status == _Status.failed
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          if (r.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  r.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: r.status == _Status.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
