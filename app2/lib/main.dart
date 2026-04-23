import 'package:flutter/material.dart';
import 'screens/connection/connection_screen.dart';

void main() {
  runApp(const App2());
}

class App2 extends StatelessWidget {
  const App2({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma 4 Chat',
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
