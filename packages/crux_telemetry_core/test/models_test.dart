// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry_core/crux_telemetry_core.dart';
import 'package:test/test.dart';

enum _Sample { xPropagationChain, ieee754Single, parseHTMLDoc, plain }

/// The moved models, held here too so this package's own coverage covers
/// them; crux_telemetry's suite keeps testing them through its re-exports.
void main() {
  group('TelemetryEvent', () {
    final at = DateTime.utc(2026, 11, 23);

    test('equal by name, properties and time; properties are a copy', () {
      final props = <String, Object?>{'tool': 'info'};
      final a = TelemetryEvent(
        'mcp.tool_call',
        properties: props,
        timestamp: at,
      );
      props['tool'] = 'search';
      final b = TelemetryEvent(
        'mcp.tool_call',
        properties: const {'tool': 'info'},
        timestamp: at,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(TelemetryEvent('mcp.tool_call', timestamp: at)));
      expect(
        a,
        isNot(
          TelemetryEvent(
            'mcp.tool_call',
            properties: const {'outcome': 'info'},
            timestamp: at,
          ),
        ),
      );
      expect(
        a,
        isNot(
          TelemetryEvent(
            'mcp.tool_call',
            properties: const {'tool': 'search'},
            timestamp: at,
          ),
        ),
      );
      expect(() => a.properties['x'] = 1, throwsUnsupportedError);
      expect(a.toString(), contains('mcp.tool_call'));
    });
  });

  test('telemetryEnumToken snake-cases an enum name', () {
    // Hand-derived from the doc comment's own examples.
    expect(
      telemetryEnumToken(_Sample.xPropagationChain),
      'x_propagation_chain',
    );
    expect(telemetryEnumToken(_Sample.ieee754Single), 'ieee754_single');
    expect(telemetryEnumToken(_Sample.parseHTMLDoc), 'parse_html_doc');
    expect(telemetryEnumToken(_Sample.plain), 'plain');
  });

  test('the no-op service discards', () {
    const NoopTelemetryService().record(TelemetryEvent('a.b'));
  });

  test(
    'InMemoryTelemetryStorage, and reset removes only the consent',
    () async {
      final storage = InMemoryTelemetryStorage({
        kTelemetryConsentKey: 'enabled',
        kTelemetryInstallationIdKey: 'id',
      });
      expect(await storage.read(kTelemetryConsentKey), 'enabled');
      await storage.write('k', 'v');
      expect(storage.values['k'], 'v');
      await resetTelemetryConsent(storage);
      expect(await storage.read(kTelemetryConsentKey), isNull);
      expect(await storage.read(kTelemetryInstallationIdKey), 'id');
    },
  );

  test('a row too large to send on its own is dropped, not sent', () {
    final envelope = TelemetryEnvelope(
      installationId: '00000000-0000-4000-8000-00000000000a',
      appVersion: '2.0.0',
      product: 'wavecrux',
      os: 'linux',
      formFactor: 'desktop',
      locale: 'en',
      licenseTier: 'openCore',
      sessionStart: DateTime.utc(2026, 11, 23),
      userAgentName: 'WaveCrux',
    );
    final huge = TelemetryBatchEntry(
      name: 'a.b',
      properties: <String, Object?>{'k': 'x' * (kTelemetryMaxBatchBytes + 1)},
      count: 1,
    );
    const small = TelemetryBatchEntry(
      name: 'a.c',
      properties: <String, Object?>{},
      count: 1,
    );
    final batches = buildTelemetryBatches(envelope, [huge, small]);
    expect(batches.single.entries.single.name, 'a.c');
    final many = List<TelemetryBatchEntry>.filled(
      kTelemetryMaxBatchEvents + 1,
      small,
    );
    expect(buildTelemetryBatches(envelope, many), hasLength(2));
    expect(buildTelemetryBatches(envelope, const []), isEmpty);
  });
}
