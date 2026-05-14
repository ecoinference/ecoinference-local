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
    // torch_light uses CameraManager.setTorchMode() on Android, which does NOT
    // require CAMERA permission. Skipping isTorchAvailable() — it can return
    // false on MIUI/custom ROMs even when a torch is present.
    if (on) {
      await TorchLight.enableTorch();
      return 'Flashlight turned on.';
    } else {
      await TorchLight.disableTorch();
      return 'Flashlight turned off.';
    }
  } on Exception catch (e) {
    final msg = e.toString();
    if (msg.contains('device_not_capable')) {
      return 'Flashlight is not accessible on this device (device_not_capable). '
          'Try toggling it manually first, or the ROM may be blocking torch access.';
    }
    return 'Flashlight error: $e';
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
