import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'app.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init();

  // Initialise flutter_gemma with the stored HuggingFace token so that any
  // fromNetwork() call is automatically authenticated.  maxDownloadRetries
  // defaults to 10 but is explicit here for clarity.
  final hfToken = SettingsService.instance.hfToken;
  await FlutterGemma.initialize(
    huggingFaceToken: hfToken.isNotEmpty ? hfToken : null,
    maxDownloadRetries: 10,
  );

  runApp(const App());
}
