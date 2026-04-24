import 'package:flutter/material.dart';
import 'screens/home/home_screen.dart';
import 'screens/setup/setup_screen.dart';
import 'services/settings_service.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4285F4), // Google Blue
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4285F4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      initialRoute:
          SettingsService.instance.setupDone ? '/home' : '/setup',
      routes: {
        '/setup': (_) => const SetupScreen(),
        '/home': (_) => const HomeScreen(),
      },
    );
  }
}
