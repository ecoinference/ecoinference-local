import 'package:flutter_test/flutter_test.dart';
import 'package:ai_client/models/server_config.dart';
import 'package:ai_client/services/api_service.dart';

/// Smoke tests for the ApiService singleton.
///
/// These tests do NOT make real network calls — they only verify the
/// singleton lifecycle and configuration behaviour.
void main() {
  // Use a loopback address that will refuse connections immediately so any
  // accidental network call fails fast rather than timing out.
  const _cfg = ServerConfig(host: '127.0.0.1', port: 19999);
  const _cfg2 = ServerConfig(host: '10.0.0.1', port: 8080, modelId: 'alt');

  // ── Singleton lifecycle ─────────────────────────────────────────────────────

  group('ApiService singleton', () {
    // NOTE: static state persists within the test process, so we run the
    // "before configure" check first (guaranteed to be the initial state in
    // a fresh test run) and then keep the instance configured for the rest.

    test('instance throws StateError before configure() is called', () {
      // Reset: tests run in process-order; this must be the first test.
      // If the singleton was already configured by a previous test run,
      // skip this assertion to avoid a false failure.
      if (!ApiService.isConfigured) {
        expect(() => ApiService.instance, throwsA(isA<StateError>()));
      }
    });

    test('isConfigured is false before configure() and true after', () {
      if (!ApiService.isConfigured) {
        expect(ApiService.isConfigured, isFalse);
      }
      ApiService.configure(_cfg);
      expect(ApiService.isConfigured, isTrue);
    });

    test('instance returns the configured service', () {
      ApiService.configure(_cfg);
      final svc = ApiService.instance;
      expect(svc.config.host, _cfg.host);
      expect(svc.config.port, _cfg.port);
    });

    test('configure() replaces the previous instance', () {
      ApiService.configure(_cfg);
      ApiService.configure(_cfg2);
      expect(ApiService.instance.config.host, _cfg2.host);
      expect(ApiService.instance.config.port, _cfg2.port);
      expect(ApiService.instance.config.modelId, _cfg2.modelId);
    });

    test('configure() twice in a row does not throw', () {
      expect(() {
        ApiService.configure(_cfg);
        ApiService.configure(_cfg);
      }, returnsNormally);
    });

    test('instance is the same object between calls (no re-creation)', () {
      ApiService.configure(_cfg);
      final a = ApiService.instance;
      final b = ApiService.instance;
      expect(identical(a, b), isTrue);
    });

    test('configure() with new config returns different object', () {
      ApiService.configure(_cfg);
      final a = ApiService.instance;
      ApiService.configure(_cfg2);
      final b = ApiService.instance;
      expect(identical(a, b), isFalse);
    });
  });

  // ── Config propagation ──────────────────────────────────────────────────────

  group('ApiService config', () {
    setUp(() => ApiService.configure(_cfg));

    test('baseUrl matches configured host and port', () {
      expect(ApiService.instance.config.baseUrl, 'http://127.0.0.1:19999');
    });

    test('modelId defaults to "gemma4"', () {
      expect(ApiService.instance.config.modelId, 'gemma4');
    });

    test('modelId reflects custom value passed to configure()', () {
      ApiService.configure(
        const ServerConfig(host: '127.0.0.1', port: 8080, modelId: 'gemma4-e4b'),
      );
      expect(ApiService.instance.config.modelId, 'gemma4-e4b');
    });
  });
}
