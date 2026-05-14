import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tool_definition.dart';

/// Registers all hardware tools into [ToolRegistry].
/// Call once from [main()] or the first screen's [initState].
void registerHardwareTools() {
  ToolRegistry.register(const ToolDefinition(
    name: 'flashlight',
    description: 'Turn the device torch/flashlight on or off.',
    parametersDoc: 'on: bool',
    argsExample: '{"on": true}',
    execute: _flashlight,
    requiresConfirmation: false,
  ));

  ToolRegistry.register(const ToolDefinition(
    name: 'get_location',
    description: 'Get the device current GPS coordinates, accuracy, and altitude.',
    parametersDoc: '(no parameters)',
    argsExample: '{}',
    execute: _getLocation,
    requiresConfirmation: false,
  ));

  ToolRegistry.register(const ToolDefinition(
    name: 'show_map',
    description:
        'Get the current GPS location and open it in Google Maps so the user can see it.',
    parametersDoc: '(no parameters)',
    argsExample: '{}',
    execute: _showMap,
    requiresConfirmation: false,
  ));

  ToolRegistry.register(const ToolDefinition(
    name: 'send_sos',
    description:
        'Flash the device torch in the international SOS Morse code pattern '
        '(· · · — — — · · ·) to signal for help.',
    parametersDoc: '(no parameters)',
    argsExample: '{}',
    execute: _sendSos,
    requiresConfirmation: false,
  ));

  ToolRegistry.register(const ToolDefinition(
    name: 'send_sms',
    description:
        'Send an SMS text message. Always requires user confirmation before sending.',
    parametersDoc: 'to: string (phone number), message: string',
    argsExample: '{"to": "+15551234567", "message": "Hello!"}',
    execute: _sendSms,
    requiresConfirmation: true,
  ));
}

// ── Flashlight ────────────────────────────────────────────────────────────────

Future<String> _flashlight(Map<String, dynamic> args) async {
  final on = (args['on'] as bool?) ?? true;
  try {
    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        return 'Permission denied: camera permission is required to use the flashlight.';
      }
    }
    final available = await TorchLight.isTorchAvailable();
    if (!available) return 'Flashlight is not available on this device.';
    if (on) {
      await TorchLight.enableTorch();
      return 'Flashlight turned on.';
    } else {
      await TorchLight.disableTorch();
      return 'Flashlight turned off.';
    }
  } on Exception catch (e) {
    return 'Flashlight error: $e';
  }
}

// ── SOS Morse signal ──────────────────────────────────────────────────────────

// Standard Morse timing (ITU-R M.1677):
//   1 unit  = dot duration / inter-element gap
//   3 units = dash duration / inter-letter gap
const _morseUnit      = Duration(milliseconds: 200);
const _morseDot       = _morseUnit;
const _morseDash      = Duration(milliseconds: 600);  // 3 × unit
const _morseSymbolGap = _morseUnit;
const _morseLetterGap = Duration(milliseconds: 600);  // 3 × unit

Future<String> _sendSos(Map<String, dynamic> args) async {
  try {
    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        return 'Permission denied: camera permission is required for the torch.';
      }
    }
    final available = await TorchLight.isTorchAvailable();
    if (!available) return 'Flashlight is not available on this device.';

    // SOS: · · ·  — — —  · · ·
    // Each entry is (onDuration, offDuration after)
    final sequence = <(Duration, Duration)>[
      // S: three dots
      (_morseDot,  _morseSymbolGap),
      (_morseDot,  _morseSymbolGap),
      (_morseDot,  _morseLetterGap),   // end of S — longer gap before O
      // O: three dashes
      (_morseDash, _morseSymbolGap),
      (_morseDash, _morseSymbolGap),
      (_morseDash, _morseLetterGap),   // end of O — longer gap before S
      // S: three dots
      (_morseDot,  _morseSymbolGap),
      (_morseDot,  _morseSymbolGap),
      (_morseDot,  Duration.zero),     // final dot — no trailing gap needed
    ];

    for (final (on, off) in sequence) {
      await TorchLight.enableTorch();
      await Future.delayed(on);
      await TorchLight.disableTorch();
      if (off > Duration.zero) await Future.delayed(off);
    }

    return 'SOS signal complete (· · · — — — · · ·).';
  } on Exception catch (e) {
    // Make sure torch is off if something goes wrong mid-sequence.
    try { await TorchLight.disableTorch(); } catch (_) {}
    return 'SOS error: $e';
  }
}

// ── GPS helpers ───────────────────────────────────────────────────────────────

/// Shared location fetch used by both [_getLocation] and [_showMap].
/// Returns a [Position] on success, or a human-readable error string.
Future<Object> _fetchPosition() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return 'Location services are disabled. Please enable GPS in device settings.';
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return 'Location permission denied.';
    }
  }
  if (permission == LocationPermission.deniedForever) {
    return 'Location permission permanently denied. '
        'Enable it in device Settings → App permissions.';
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    ),
  );
}

// ── Get location ──────────────────────────────────────────────────────────────

Future<String> _getLocation(Map<String, dynamic> args) async {
  try {
    final result = await _fetchPosition();
    if (result is String) return result; // error message

    final pos = result as Position;
    final lat = pos.latitude.toStringAsFixed(6);
    final lon = pos.longitude.toStringAsFixed(6);
    final acc = pos.accuracy.toStringAsFixed(1);
    final alt = pos.altitude.toStringAsFixed(1);

    return 'Latitude: $lat, Longitude: $lon, '
        'Accuracy: ±${acc}m, Altitude: ${alt}m. '
        'Maps link: https://maps.google.com/?q=$lat,$lon';
  } on Exception catch (e) {
    return 'Location error: $e';
  }
}

// ── Show map ──────────────────────────────────────────────────────────────────

Future<String> _showMap(Map<String, dynamic> args) async {
  try {
    final result = await _fetchPosition();
    if (result is String) return result; // error message

    final pos = result as Position;
    final lat = pos.latitude.toStringAsFixed(6);
    final lon = pos.longitude.toStringAsFixed(6);
    final acc = pos.accuracy.toStringAsFixed(1);

    // geo: URI opens the default maps app on Android.
    // On iOS, url_launcher falls back to Google Maps in the browser.
    // z=17 gives a street-level zoom.
    final geoUri = Uri.parse('geo:$lat,$lon?q=$lat,$lon&z=17');
    final webUri = Uri.parse('https://maps.google.com/?q=$lat,$lon&z=17');

    final uri = (Platform.isAndroid) ? geoUri : webUri;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched) {
      // Fallback to web URL if the geo: intent isn't handled.
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }

    return 'Map opened showing current location '
        '($lat, $lon, accuracy ±${acc}m).';
  } on Exception catch (e) {
    return 'Show map error: $e';
  }
}

// ── SMS ───────────────────────────────────────────────────────────────────────

Future<String> _sendSms(Map<String, dynamic> args) async {
  final to = (args['to'] as String? ?? '').trim();
  final message = (args['message'] as String? ?? '').trim();

  if (to.isEmpty) return 'Error: recipient phone number is required.';
  if (message.isEmpty) return 'Error: message body is required.';

  // Use the sms: URI scheme via url_launcher — works on all platforms without
  // special permissions and opens the user's default SMS app.
  final uri = Uri(
    scheme: 'sms',
    path: to,
    queryParameters: {'body': message},
  );

  try {
    final launched = await launchUrl(uri);
    if (!launched) return 'Could not open SMS app for $to.';
    return 'SMS compose opened for $to — tap Send to deliver.';
  } on Exception catch (e) {
    return 'SMS error: $e';
  }
}
