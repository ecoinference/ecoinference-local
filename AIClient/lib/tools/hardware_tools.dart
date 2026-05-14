import 'dart:io';

import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:torch_light/torch_light.dart';

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
    // Android requires CAMERA permission to access the torch hardware.
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

// ── SMS ───────────────────────────────────────────────────────────────────────

Future<String> _sendSms(Map<String, dynamic> args) async {
  final to = (args['to'] as String? ?? '').trim();
  final message = (args['message'] as String? ?? '').trim();

  if (to.isEmpty) return 'Error: recipient phone number is required.';
  if (message.isEmpty) return 'Error: message body is required.';

  try {
    // sendDirect: true  → uses SmsManager on Android (silent send after confirm).
    // sendDirect: false → opens the system compose sheet on iOS (user taps Send).
    await sendSMS(
      message: message,
      recipients: [to],
      sendDirect: Platform.isAndroid,
    );
    return Platform.isAndroid
        ? 'SMS sent to $to.'
        : 'SMS compose sheet opened — tap Send to deliver.';
  } on Exception catch (e) {
    return 'SMS error: $e';
  }
}
