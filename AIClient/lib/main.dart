import 'package:flutter/material.dart';
import 'screens/connection/connection_screen.dart';
import 'services/deep_link_service.dart';
import 'theme/eco_theme.dart';

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
      title: 'EcoInference',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: EcoTheme.light(),
      darkTheme: EcoTheme.dark(),
      themeMode: ThemeMode.system,
      home: const ConnectionScreen(),
    );
  }
}
