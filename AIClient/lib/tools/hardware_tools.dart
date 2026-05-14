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

// ── GPS location ──────────────────────────────────────────────────────────────

Future<String> _getLocation(Map<String, dynamic> args) async {
  try {
    // Check if location services are enabled at the OS level.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Please enable GPS in device settings.';
    }

    // Check / request permission.
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

    // Fetch position — high accuracy, 15 s timeout.
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

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
