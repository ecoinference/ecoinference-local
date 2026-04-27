import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_client/models/server_config.dart';
import 'package:ai_client/screens/chat/chat_screen.dart';
import 'package:ai_client/screens/connection/connection_screen.dart';
import 'package:ai_client/services/api_service.dart';

/// Widget smoke tests — verify that key screens mount and render their
/// initial state without throwing, without any real network connection.
void main() {
  // Suppress SharedPreferences "MissingPluginException" in tests by
  // providing an in-memory store before each test.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Helper: wraps a widget in a minimal MaterialApp so Theme / Navigator
  // are available (required by Scaffold, SnackBar, etc.).
  Widget wrap(Widget child) => MaterialApp(home: child);

  // ── ConnectionScreen ────────────────────────────────────────────────────────

  group('ConnectionScreen', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(wrap(const ConnectionScreen()));
      // Single pump — don't wait for async initState (loads saved prefs).
      // We just verify the widget tree builds without exceptions.
    });

    testWidgets('shows host and port fields', (tester) async {
      await tester.pumpWidget(wrap(const ConnectionScreen()));
      await tester.pump(); // allow initState async to settle

      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
    });

    testWidgets('shows Connect button', (tester) async {
      await tester.pumpWidget(wrap(const ConnectionScreen()));
      await tester.pump();

      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('shows validation error for blank host', (tester) async {
      await tester.pumpWidget(wrap(const ConnectionScreen()));
      await tester.pump();

      // Clear the host field and tap Connect.
      await tester.enterText(
        find.widgetWithText(TextField, '127.0.0.1'),
        '',
      );
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.textContaining('Invalid'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows validation error for non-numeric port', (tester) async {
      await tester.pumpWidget(wrap(const ConnectionScreen()));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, '8080'),
        'abc',
      );
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.text('Invalid port number'), findsOneWidget);
    });
  });

  // ── ChatScreen ──────────────────────────────────────────────────────────────

  group('ChatScreen', () {
    const config = ServerConfig(host: '127.0.0.1', port: 8080);

    setUp(() {
      // ChatScreen uses ApiService.instance — configure before each test.
      ApiService.configure(config);
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
    });

    testWidgets('shows empty-state prompt when no messages', (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
      await tester.pump(); // allow _loadMessages async to settle

      expect(find.text('Start a conversation'), findsOneWidget);
    });

    testWidgets('shows send button in idle state', (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
      await tester.pump();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('send button is inactive when input is empty', (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
      await tester.pump();

      // Tap send with empty input — nothing should happen and no crash.
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(find.text('Start a conversation'), findsOneWidget);
    });

    testWidgets('AppBar shows server URL subtitle', (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
      await tester.pump();

      expect(find.text(config.baseUrl), findsOneWidget);
    });

    testWidgets('AppBar has system-prompt and models action buttons',
        (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
      await tester.pump();

      expect(find.byIcon(Icons.tune_outlined), findsOneWidget);
      expect(find.byIcon(Icons.model_training_outlined), findsOneWidget);
    });

    testWidgets('system prompt dialog opens and closes without crash',
        (tester) async {
      await tester.pumpWidget(wrap(ChatScreen(config: config)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();

      expect(find.text('System Prompt'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('System Prompt'), findsNothing);
    });
  });
}
