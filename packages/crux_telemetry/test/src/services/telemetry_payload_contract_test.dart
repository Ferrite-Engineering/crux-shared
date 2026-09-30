// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_license/crux_license.dart' show LicenseTier;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// THE payload contract test.
///
/// `test/fixtures/valid-batch.json` carries the same data as the ingestion
/// Worker's canonical batch document, whose acceptance the Worker's own suite
/// asserts. This file asserts this package's serializer
/// emits that same document. Hold both and the client and the Worker cannot
/// have drifted — which matters because the Worker's envelope validation is
/// all-or-nothing: one wrong field costs the user's whole queue.
void main() {
  Map<String, Object?> loadFixture() {
    final raw = File(
      'test/fixtures/valid-batch.json',
    ).readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    // Unknown top-level fields are dropped by the Worker; `_comment` exercises
    // that, and is not part of what a client emits.
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key != '_comment') entry.key: entry.value,
    };
  }

  group('serializer ↔ Worker contract', () {
    test('emits exactly the canonical batch for the equivalent inputs', () {
      final envelope = testEnvelope(
        locale: 'zh_CN',
        licenseTier: LicenseTier.openCore.name,
      );

      // The queue as the app would have written it: one restore, four SPI
      // decoder opens, two honored inbound cross-probes, one FSM tool open.
      // These names are the Worker fixture's, not this package's — nothing in
      // `lib/` knows any product's catalog.
      final queue = <TelemetryEvent>[
        TelemetryEvent('workspace.restored'),
        for (var i = 0; i < 4; i++)
          TelemetryEvent(
            'decoder.opened',
            properties: const <String, Object?>{'decoder': 'spi'},
          ),
        for (var i = 0; i < 2; i++)
          TelemetryEvent(
            'cxp.crossprobe',
            properties: const <String, Object?>{
              'direction': 'inbound',
              'honored': true,
            },
          ),
        TelemetryEvent(
          'tool.opened',
          properties: const <String, Object?>{'tool': 'fsm'},
        ),
      ];

      final batches = buildTelemetryBatches(
        envelope,
        coalesceTelemetryEvents(queue),
      );

      expect(batches, hasLength(1));
      expect(jsonDecode(batches.single.body), loadFixture());
    });

    test('key order matches the fixture, so a captured request hand-diffs', () {
      final envelope = testEnvelope(locale: 'zh_CN');
      final body =
          jsonDecode(
                encodeTelemetryBatch(envelope, const <TelemetryBatchEntry>[]),
              )
              as Map<String, Object?>;

      expect(body.keys.toList(), <String>[
        'installation_id',
        'app_version',
        'product',
        'os',
        'form_factor',
        'locale',
        'license_tier',
        'session_start',
        'events',
      ]);
    });

    test('session_start is whole-second ISO-8601 UTC', () {
      // The Worker bounds the field at 32 characters, and sub-second
      // precision on a session start is precision about a person that nothing
      // downstream reads.
      expect(
        telemetryIso8601(DateTime.utc(2026, 8, 4, 9, 15, 0, 123, 456)),
        '2026-08-04T09:15:00Z',
      );
      expect(
        telemetryIso8601(
          DateTime.utc(2026, 8, 4, 9, 15).add(const Duration(hours: 2)),
        ),
        '2026-08-04T11:15:00Z',
      );
    });

    test('the closed envelope vocabularies match the Worker enums', () {
      expect(testTelemetryConfig.productSlug, 'wavecrux');
      expect(kTelemetryOperatingSystems, <String>[
        'macos',
        'windows',
        'linux',
        'ios',
        'android',
        'web',
      ]);
      expect(kTelemetryFormFactors, <String>[
        'desktop',
        'phone',
        'tablet',
        'web',
        'vscode',
      ]);
      // A tier added to the enum without a matching Worker entry would reject
      // every batch that tier ever sends — fail here instead.
      expect(
        LicenseTier.values.map((tier) => tier.name).toList(),
        kTelemetryLicenseTiers,
      );
    });
  });

  group('the never-collect list, in the negative direction', () {
    /// The Worker's `PROPERTY_VALUE` class. A value outside it cannot describe
    /// a file, a signal, a scope, or a rule message.
    final propertyValue = RegExp(r'^[a-z0-9_]{1,64}$');
    final eventName = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$');

    test('a path, a signal name, or capitals never survive as a value', () {
      const forbidden = <String>[
        '/Users/jane/designs/cpu_top.vcd',
        r'C:\work\dump.fst',
        'top.cpu.alu.result[31:0]',
        'CPU_TOP',
        'clk gate enable',
        'martin@example.com',
        '192.168.1.42',
      ];
      for (final value in forbidden) {
        expect(
          propertyValue.hasMatch(value),
          isFalse,
          reason: '$value must not be emittable as a property value',
        );
      }
    });

    test('the catalog vocabulary does survive', () {
      for (final value in <String>['spi', 'i2c', 'vcd', 'fsm', 'inbound']) {
        expect(propertyValue.hasMatch(value), isTrue);
      }
      for (final name in <String>[
        'workspace.restored',
        'decoder.opened',
        'debugadvisor.suggestion.accepted',
      ]) {
        expect(eventName.hasMatch(name), isTrue);
      }
    });

    test('a batch built from forbidden inputs carries them nowhere legal', () {
      // The client does not sanitize — it has no business rewriting a call
      // site's event. What it guarantees is that such a value can only ever be
      // *dropped* by the Worker, never stored: this asserts the emitted JSON is
      // the only thing between the call site and that validation, so a catalog
      // conformance failure is visible rather than silently laundered.
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        TelemetryEvent(
          'file.opened',
          properties: const <String, Object?>{
            'format': 'vcd',
            'path': '/Users/jane/designs/cpu_top.vcd',
          },
        ),
      ]);

      final emitted = entries.single.toJson();
      final properties = emitted['properties']! as Map<String, Object?>;
      final offending = properties.entries.where(
        (e) => e.value is String && !propertyValue.hasMatch(e.value! as String),
      );

      expect(
        offending.map((e) => e.key),
        <String>['path'],
        reason:
            'the emitted payload must expose an off-vocabulary value to the '
            "Worker's validation rather than reshaping it into something that "
            'passes',
      );
    });
  });
}
