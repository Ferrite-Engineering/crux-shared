// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  final envelope = testEnvelope();

  TelemetryEvent event(String name, [Map<String, Object?>? properties]) =>
      TelemetryEvent(name, properties: properties);

  group('coalesceTelemetryEvents', () {
    test('folds identical (name, properties) pairs into one count', () {
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('decoder.opened', <String, Object?>{'decoder': 'spi'}),
        event('decoder.opened', <String, Object?>{'decoder': 'spi'}),
        event('decoder.opened', <String, Object?>{'decoder': 'spi'}),
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.count, 3);
      expect(entries.single.name, 'decoder.opened');
    });

    test('keeps differing property values apart', () {
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('decoder.opened', <String, Object?>{'decoder': 'spi'}),
        event('decoder.opened', <String, Object?>{'decoder': 'i2c'}),
        event('decoder.opened', <String, Object?>{'decoder': 'spi'}),
      ]);

      expect(entries, hasLength(2));
      expect(entries[0].properties['decoder'], 'spi');
      expect(entries[0].count, 2);
      expect(entries[1].properties['decoder'], 'i2c');
      expect(entries[1].count, 1);
    });

    test('coalesces regardless of the order the maps were built in', () {
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('cxp.crossprobe', <String, Object?>{
          'direction': 'inbound',
          'honored': true,
        }),
        event('cxp.crossprobe', <String, Object?>{
          'honored': true,
          'direction': 'inbound',
        }),
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.count, 2);
      // Sorted by key, so the encoding is deterministic and groupable in SQL.
      expect(entries.single.properties.keys, <String>['direction', 'honored']);
    });

    test('rows come back in first-occurrence order', () {
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('tab.opened'),
        event('pane.split'),
        event('tab.opened'),
      ]);
      expect(entries.map((e) => e.name), <String>['tab.opened', 'pane.split']);
    });

    test('drops null property values rather than emitting them', () {
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('tool.opened', <String, Object?>{'tool': 'fsm', 'extra': null}),
      ]);
      expect(entries.single.properties, <String, Object?>{'tool': 'fsm'});
    });

    test('emits no properties key for a property-less event', () {
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('workspace.restored'),
      ]);
      expect(entries.single.toJson().containsKey('properties'), isFalse);
      expect(entries.single.toJson(), <String, Object?>{
        'name': 'workspace.restored',
        'count': 1,
      });
    });

    test('no client timestamp survives into a batch row', () {
      // Per-event timestamps would be an interaction sequence, which is not
      // collected; the row
      // carries a count and nothing else temporal.
      final entries = coalesceTelemetryEvents(<TelemetryEvent>[
        event('tab.opened'),
      ]);
      expect(entries.single.toJson().keys, <String>['name', 'count']);
    });
  });

  group('buildTelemetryBatches', () {
    List<TelemetryBatchEntry> rows(int n) => <TelemetryBatchEntry>[
      for (var i = 0; i < n; i++)
        TelemetryBatchEntry(
          name: 'tool.opened',
          properties: <String, Object?>{'tool': 'fsm', 'seq': i},
          count: 1,
        ),
    ];

    test('produces nothing for an empty queue', () {
      expect(buildTelemetryBatches(envelope, const []), isEmpty);
    });

    test('one POST when everything fits', () {
      final batches = buildTelemetryBatches(envelope, rows(10));
      expect(batches, hasLength(1));
      expect(batches.single.entries, hasLength(10));
    });

    test('splits at the 500-event cap', () {
      final batches = buildTelemetryBatches(envelope, rows(1200));

      expect(batches, hasLength(3));
      expect(batches[0].entries, hasLength(kTelemetryMaxBatchEvents));
      expect(batches[1].entries, hasLength(kTelemetryMaxBatchEvents));
      expect(batches[2].entries, hasLength(200));
      for (final batch in batches) {
        final decoded = jsonDecode(batch.body) as Map<String, Object?>;
        expect(
          (decoded['events']! as List<Object?>).length,
          lessThanOrEqualTo(500),
        );
      }
    });

    test('splits at the 64 KB cap, and every body is under it', () {
      // Six 64-character property values is the widest row the Worker's
      // property class admits, so this is the densest legal batch — dense
      // enough that the size cap bites before the 500-event cap does.
      final wide = <TelemetryBatchEntry>[
        for (var i = 0; i < 500; i++)
          TelemetryBatchEntry(
            name: 'stage.widget_added',
            properties: <String, Object?>{
              for (var p = 0; p < 6; p++)
                'prop$p': 'w${i}_$p'.padRight(64, 'x'),
            },
            count: 1,
          ),
      ];

      final batches = buildTelemetryBatches(envelope, wide);

      expect(batches.length, greaterThan(1));
      for (final batch in batches) {
        expect(batch.entries.length, lessThan(kTelemetryMaxBatchEvents));
        expect(
          utf8.encode(batch.body).length,
          lessThanOrEqualTo(kTelemetryMaxBatchBytes),
        );
      }
      // Nothing is lost to the split.
      expect(
        batches.fold<int>(0, (sum, b) => sum + b.entries.length),
        wide.length,
      );
    });

    test('the encoded body is exactly the envelope plus its rows', () {
      final batches = buildTelemetryBatches(envelope, rows(3));
      final decoded = jsonDecode(batches.single.body) as Map<String, Object?>;

      expect(decoded['installation_id'], envelope.installationId);
      expect(decoded['product'], testTelemetryConfig.productSlug);
      expect(decoded['events']! as List<Object?>, hasLength(3));
    });

    test('the caps match the Worker constants', () {
      expect(kTelemetryMaxBatchEvents, 500);
      expect(kTelemetryMaxBatchBytes, 64 * 1024);
    });
  });
}
