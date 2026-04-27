import 'package:flutter_test/flutter_test.dart';
import 'package:ai_client/models/chat_message.dart';
import 'package:ai_client/models/download_progress.dart';
import 'package:ai_client/models/model_info.dart';
import 'package:ai_client/models/server_config.dart';

void main() {
  // ── ServerConfig ────────────────────────────────────────────────────────────

  group('ServerConfig', () {
    test('baseUrl combines host and port', () {
      const cfg = ServerConfig(host: '192.168.1.10', port: 9090);
      expect(cfg.baseUrl, 'http://192.168.1.10:9090');
    });

    test('defaults to localhost:8080', () {
      const cfg = ServerConfig();
      expect(cfg.baseUrl, 'http://127.0.0.1:8080');
    });

    test('copyWith replaces only specified fields', () {
      const cfg = ServerConfig(host: '10.0.0.1', port: 8080, modelId: 'A');
      final updated = cfg.copyWith(port: 9000);
      expect(updated.host, '10.0.0.1');
      expect(updated.port, 9000);
      expect(updated.modelId, 'A');
    });

    test('copyWith modelId leaves host and port unchanged', () {
      const cfg = ServerConfig(host: '1.2.3.4', port: 1234);
      final updated = cfg.copyWith(modelId: 'gemma4-e4b');
      expect(updated.host, '1.2.3.4');
      expect(updated.port, 1234);
      expect(updated.modelId, 'gemma4-e4b');
    });
  });

  // ── ChatMessage ─────────────────────────────────────────────────────────────

  group('ChatMessage', () {
    test('toJson / fromJson roundtrip preserves all fields', () {
      final original = ChatMessage(
        role: MessageRole.user,
        content: 'Hello, world!',
        timestamp: DateTime(2025, 1, 15, 10, 30),
      );
      final json = original.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, MessageRole.user);
      expect(restored.content, 'Hello, world!');
      expect(
        restored.timestamp.millisecondsSinceEpoch,
        original.timestamp.millisecondsSinceEpoch,
      );
    });

    test('fromJson with null timestamp falls back to a recent time', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final msg = ChatMessage.fromJson({
        'role': 'assistant',
        'content': 'Hi',
        'timestamp': null,
      });
      expect(msg.timestamp.isAfter(before), isTrue);
    });

    test('toApiJson includes only role and content — no timestamp', () {
      final msg = ChatMessage(role: MessageRole.system, content: 'Be helpful.');
      final api = msg.toApiJson();
      expect(api['role'], 'system');
      expect(api['content'], 'Be helpful.');
      expect(api.containsKey('timestamp'), isFalse);
    });

    test('isUser / isAssistant flags are correct', () {
      final user = ChatMessage(role: MessageRole.user, content: '');
      final assistant = ChatMessage(role: MessageRole.assistant, content: '');
      final system = ChatMessage(role: MessageRole.system, content: '');

      expect(user.isUser, isTrue);
      expect(user.isAssistant, isFalse);
      expect(assistant.isAssistant, isTrue);
      expect(assistant.isUser, isFalse);
      expect(system.isUser, isFalse);
      expect(system.isAssistant, isFalse);
    });

    test('all MessageRole variants survive fromJson roundtrip', () {
      for (final role in MessageRole.values) {
        final json = {'role': role.name, 'content': 'x'};
        expect(ChatMessage.fromJson(json).role, role);
      }
    });
  });

  // ── ModelInfo ───────────────────────────────────────────────────────────────

  group('ModelInfo', () {
    const _sampleJson = {
      'id': 'gemma4-e2b-it',
      'name': 'Gemma 4 E2B',
      'file_name': 'gemma4-e2b-it.litertlm',
      'size_gb': 2.5,
      'platform': 'android',
      'downloaded': true,
      'loaded': false,
    };

    test('fromJson parses all fields', () {
      final model = ModelInfo.fromJson(_sampleJson);
      expect(model.id, 'gemma4-e2b-it');
      expect(model.name, 'Gemma 4 E2B');
      expect(model.fileName, 'gemma4-e2b-it.litertlm');
      expect(model.sizeGb, 2.5);
      expect(model.platform, 'android');
      expect(model.downloaded, isTrue);
      expect(model.loaded, isFalse);
    });

    test('fromJson defaults downloaded and loaded to false when absent', () {
      final model = ModelInfo.fromJson({
        'id': 'x',
        'name': 'X',
        'file_name': 'x.litertlm',
        'size_gb': 1.0,
        'platform': 'android',
      });
      expect(model.downloaded, isFalse);
      expect(model.loaded, isFalse);
    });

    test('copyWith updates only specified live-state fields', () {
      final base = ModelInfo.fromJson(_sampleJson);
      final updated = base.copyWith(loaded: true);
      expect(updated.loaded, isTrue);
      expect(updated.downloaded, isTrue); // unchanged
      expect(updated.id, base.id);        // unchanged
    });
  });

  // ── DownloadProgress ────────────────────────────────────────────────────────

  group('DownloadProgress', () {
    test('fromJson parses all fields', () {
      final p = DownloadProgress.fromJson({
        'model_id': 'gemma4-e2b-it',
        'status': 'downloading',
        'percent': 42,
        'bytes_received': 1073741824, // 1 GB
        'total_bytes': 2684354560,    // 2.5 GB
      });
      expect(p.modelId, 'gemma4-e2b-it');
      expect(p.status, 'downloading');
      expect(p.percent, 42);
      expect(p.bytesReceived, 1073741824);
      expect(p.totalBytes, 2684354560);
      expect(p.error, isNull);
    });

    test('isTerminal is false for "downloading"', () {
      final p = DownloadProgress.fromJson(
          {'model_id': 'x', 'status': 'downloading'});
      expect(p.isTerminal, isFalse);
    });

    test('isTerminal is true for all terminal statuses', () {
      for (final status in ['complete', 'error', 'cancelled']) {
        final p = DownloadProgress.fromJson({'model_id': 'x', 'status': status});
        expect(p.isTerminal, isTrue, reason: 'status=$status should be terminal');
      }
    });

    test('fromJson defaults numeric fields to zero when absent', () {
      final p = DownloadProgress.fromJson({'model_id': 'x', 'status': 'complete'});
      expect(p.percent, 0);
      expect(p.bytesReceived, 0);
      expect(p.totalBytes, 0);
    });

    test('fromJson handles double bytes fields from JSON decoder', () {
      // JSON numbers without decimal points can be decoded as double on some
      // platforms (e.g. 1.0e9). The num? cast in fromJson must handle this.
      final p = DownloadProgress.fromJson({
        'model_id': 'x',
        'status': 'downloading',
        'percent': 10,
        'bytes_received': 1.0e8,  // double
        'total_bytes': 4.0e9,     // double > int.maxValue on 32-bit
      });
      expect(p.bytesReceived, 100000000);
      expect(p.totalBytes, 4000000000);
    });
  });
}
