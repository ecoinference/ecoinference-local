import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'tool_result.dart';

/// Singleton that hosts a hidden Pyodide WebView and executes Python snippets.
///
/// Usage:
///   1. Call [initialize] once (e.g. in ChatScreen.initState).
///   2. Add [widget] to the widget tree inside an [Offstage].
///   3. Call [execute] to run Python code.
class PythonRunner {
  PythonRunner._();
  static final instance = PythonRunner._();

  late final WebViewController _controller;
  final _readyCompleter = Completer<void>();
  Completer<ToolResult>? _pending;
  bool _busy = false;

  bool get isInitialized => _readyCompleter.isCompleted;

  // ── Init ───────────────────────────────────────────────────────────────────

  void initialize() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('PythonResult', onMessageReceived: _onMessage)
      ..loadFlutterAsset('assets/python_runner.html');
  }

  /// The WebView widget — embed in an [Offstage] somewhere in the tree.
  Widget get widget => WebViewWidget(controller: _controller);

  // ── Message handler ────────────────────────────────────────────────────────

  void _onMessage(JavaScriptMessage msg) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'] as String? ?? '';

    switch (type) {
      case 'ready':
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        return;
      case 'status':
        // Status updates (package loading) — ignore for now.
        return;
    }

    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _pending = null;
    _busy = false;

    switch (type) {
      case 'text':
        pending.complete(TextToolResult(data['value'] as String? ?? ''));
      case 'image':
        pending.complete(ImageToolResult(base64DataUrl: data['value'] as String? ?? ''));
      case 'html':
        pending.complete(HtmlToolResult(html: data['value'] as String? ?? ''));
      case 'error':
        pending.complete(TextToolResult('Python error: ${data['value']}'));
      default:
        pending.complete(const TextToolResult('Unknown response from Python runtime.'));
    }
  }

  // ── Execute ────────────────────────────────────────────────────────────────

  Future<ToolResult> execute(String code) async {
    if (code.trim().isEmpty) return const TextToolResult('Error: no code provided.');

    // Wait for Pyodide to be ready (up to 60 s to account for CDN load).
    try {
      await _readyCompleter.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      return const TextToolResult('Python runtime did not initialise in time. Check network.');
    }

    if (_busy) return const TextToolResult('Python is already running — please wait.');

    _busy = true;
    _pending = Completer<ToolResult>();

    await _controller.runJavaScript('runPython(${jsonEncode(code)})');

    return _pending!.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _pending = null;
        _busy = false;
        return const TextToolResult('Python execution timed out (90 s).');
      },
    );
  }
}
