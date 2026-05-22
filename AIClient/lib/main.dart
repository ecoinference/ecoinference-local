import 'package:flutter/material.dart';
import 'screens/connection/connection_screen.dart';
import 'services/deep_link_service.dart';

/// Global navigator key used by [DeepLinkService] to route incoming
/// `aiclient://` links to the currently active screen.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeepLinkService.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma 4 Chat',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4285F4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4285F4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const ConnectionScreen(),
    );
  }
}
