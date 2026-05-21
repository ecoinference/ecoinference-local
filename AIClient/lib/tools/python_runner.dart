import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'tool_result.dart';

/// Singleton that hosts a hidden Pyodide WebView and executes Python snippets.
///
/// Usage:
///   1. Call [initialize] once (e.g. in ChatScreen.initState).
///   2. Add [widget] to the widget tree (1×1 Positioned, NOT Offstage).
///   3. Call [execute] to run Python code; call [cancel] to abort it.
class PythonRunner {
  PythonRunner._();
  static final instance = PythonRunner._();

  WebViewController? _controller;
  final _readyCompleter = Completer<void>();
  Completer<ToolResult>? _pending;
  bool _busy = false;
  void Function(String)? _onProgress;

  bool get isInitialized => _readyCompleter.isCompleted;

  // ── Init ───────────────────────────────────────────────────────────────────

  /// Safe to call multiple times — only the first call takes effect.
  ///
  /// This is a singleton: [ChatScreen.initState] calls this every time the
  /// screen is recreated (e.g. after backgrounding the app), but the
  /// WebViewController must only be created once.
  void initialize() {
    if (_controller != null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('PythonResult', onMessageReceived: _onMessage)
      ..loadFlutterAsset('assets/python_runner.html');
  }

  Widget get widget => WebViewWidget(controller: _controller!);

  // ── Cancel ─────────────────────────────────────────────────────────────────

  /// Immediately resolves any pending [execute] call with a "Cancelled" result.
  /// Safe to call at any time; no-op if nothing is running.
  void cancel() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      _busy = false;
      _onProgress = null;
      pending.complete(const TextToolResult('Cancelled.'));
    }
  }

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
        _onProgress?.call(data['value'] as String? ?? '');
        return;
      case 'error':
        // Pyodide init failure arrives before any execute() call.
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.completeError(
              Exception(data['value'] as String? ?? 'Pyodide init error'));
          return;
        }
    }

    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _pending = null;
    _busy = false;

    switch (type) {
      case 'text':
        pending.complete(TextToolResult(data['value'] as String? ?? ''));
      case 'image':
        pending.complete(
            ImageToolResult(base64DataUrl: data['value'] as String? ?? ''));
      case 'html':
        pending.complete(HtmlToolResult(html: data['value'] as String? ?? ''));
      case 'error':
        pending.complete(TextToolResult(_formatError(data['value'] as String? ?? '')));
      default:
        pending.complete(
            const TextToolResult('Unknown response from Python runtime.'));
    }
  }

  // ── Error formatting ───────────────────────────────────────────────────────

  /// Converts a raw Pyodide error string into a user-friendly message
  /// followed by the full technical detail for debugging.
  static String _formatError(String raw) {
    final friendly = _friendlyMessage(raw);
    return '$friendly\n\nTechnical details:\n$raw';
  }

  static String _friendlyMessage(String raw) {
    // ImportError: cannot import name 'X' from 'Y'
    final importNameMatch =
        RegExp(r"cannot import name '([^']+)' from '([^']+)'").firstMatch(raw);
    if (importNameMatch != null) {
      final name = importNameMatch.group(1)!;
      final fromMod = importNameMatch.group(2)!;
      return "❌ Import error: '$name' does not exist in '$fromMod'.\n"
          "The function or class name is wrong — check the correct API for that library.";
    }

    // ModuleNotFoundError / ImportError — module itself missing
    final modMatch = RegExp(r"No module named '([^']+)'").firstMatch(raw);
    if (modMatch != null) {
      final mod = modMatch.group(1)!;
      return "❌ Module not found: '$mod' is not installed or the import path is wrong.\n"
          "Check that the library name matches one of the supported libraries and that the import path is correct.";
    }

    // NameError
    final nameMatch = RegExp(r"NameError: name '([^']+)' is not defined").firstMatch(raw);
    if (nameMatch != null) {
      final name = nameMatch.group(1)!;
      return "❌ Name error: '$name' was used before it was defined.\n"
          "The generated code may be missing an import statement or variable assignment.";
    }

    // AttributeError
    final attrMatch = RegExp(r"AttributeError: .*'([^']+)'").firstMatch(raw);
    if (attrMatch != null) {
      return "❌ Attribute error: the code accessed a property or method that doesn't exist.\n"
          "This usually means an incorrect API call for the chosen library.";
    }

    // SyntaxError
    if (raw.contains('SyntaxError')) {
      return "❌ Syntax error: the generated code contains invalid Python syntax.";
    }

    // TypeError
    if (raw.contains('TypeError')) {
      return "❌ Type error: the code passed an unexpected type of value to a function.";
    }

    // ZeroDivisionError
    if (raw.contains('ZeroDivisionError')) {
      return "❌ Division by zero: the code attempted to divide by zero.";
    }

    // ValueError
    if (raw.contains('ValueError')) {
      return "❌ Value error: the code passed an invalid value to a function.";
    }

    // IndexError / KeyError
    if (raw.contains('IndexError') || raw.contains('KeyError')) {
      return "❌ Index/key error: the code accessed a list index or dictionary key that doesn't exist.";
    }

    // Timeout (from JS withTimeout)
    if (raw.toLowerCase().contains('timed out')) {
      return "❌ Execution timed out: the code took too long to complete.\n"
          "This may be due to a slow network while loading packages, or code that runs indefinitely.";
    }

    // Generic fallback
    return "❌ The code ran into an error. See technical details below.";
  }

  // ── Execute ────────────────────────────────────────────────────────────────

  /// Runs [code] in Pyodide. [onProgress] receives live status strings
  /// (init, package loading, execution). Always resolves — never throws.
  Future<ToolResult> execute(String code,
      {void Function(String status)? onProgress}) async {
    if (code.trim().isEmpty) {
      return const TextToolResult('Error: no code provided.');
    }

    _onProgress = onProgress;

    try {
      // ── Wait for Pyodide (max 30 s for CDN download) ─────────────────────
      if (!_readyCompleter.isCompleted) {
        _onProgress?.call('Initialising Python runtime…');
      }
      try {
        await _readyCompleter.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        return const TextToolResult(
            'Python runtime did not initialise in time. Check network.');
      } catch (e) {
        return TextToolResult('Python runtime failed to start: $e');
      }

      if (_busy) {
        return const TextToolResult('Python is already running — please wait.');
      }

      _onProgress?.call('Running…');
      _busy = true;
      _pending = Completer<ToolResult>();

      try {
        await _controller!.runJavaScript('runPython(${jsonEncode(code)})');
      } catch (e) {
        return TextToolResult('Failed to start Python execution: $e');
      }

      // Await JS result (max 60 s). JS-side withTimeout fires at 55 s so the
      // error message from JS always arrives before this Dart timeout.
      return await _pending!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _pending = null;
          return const TextToolResult('Python execution timed out (60 s).');
        },
      );
    } catch (e) {
      // Catch-all — should never happen, but guarantees the caller always
      // gets a result rather than an unhandled exception.
      return TextToolResult('Unexpected error in Python runner: $e');
    } finally {
      // Always reset runner state so the next call starts clean.
      _busy = false;
      _pending = null;
      _onProgress = null;
    }
  }
}
