// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

/// Upstream's own unit-test vectors, transcribed (see the fixtures'
/// PROVENANCE.md).
Map<String, Object?> _upstreamVectors() {
  final file = File('test/fixtures/metrics/upstream_vectors.json');
  expect(file.existsSync(), isTrue, reason: 'fixture missing');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

void main() {
  group('MetricKey', () {
    test("upstream's parse_metric_modifiers vectors", () {
      final vectors =
          _upstreamVectors()['parse_metric_modifiers']! as List<Object?>;
      expect(vectors, hasLength(3));
      for (final v in vectors.cast<Map<String, Object?>>()) {
        final key = MetricKey.tryParse(v['input']! as String)!;
        expect(key.base, v['base'], reason: '${v['input']}');
        expect(
          [
            for (final m in key.modifiers) [m.name, m.value],
          ],
          v['modifiers'],
          reason: '${v['input']}',
        );
      }
    });

    test('parse and format round-trip on real METRICS2.1 keys', () {
      for (final name in [
        'timing__setup__ws',
        'timing__setup__ws__corner:nom_tt_025C_1v80',
        'route__drc_errors__iter:3',
        'design__instance__count__class:buffer',
        'power__total__corner:max_ss_100C_1v60__vt:lvt',
        'a__',
        '',
      ]) {
        final key = MetricKey.tryParse(name)!;
        expect(key.format(), name);
        expect('$key', name);
        expect(MetricKey.tryParse(key.format()), key);
        expect(MetricKey.tryParse(name).hashCode, key.hashCode);
      }
    });

    test('modifiers keep left-to-right order', () {
      final key = MetricKey.tryParse('p__total__corner:x__vt:lvt__mode:a')!;
      expect(key.base, 'p__total');
      expect(key.modifiers.map((m) => '$m'), ['corner:x', 'vt:lvt', 'mode:a']);
      expect(key.modifier('vt'), 'lvt');
      expect(key.modifier('missing'), isNull);
      expect(key.isModified, isTrue);
      expect(MetricKey.tryParse('timing__setup__ws')!.isModified, isFalse);
    });

    test('only trailing colon segments are modifiers', () {
      final key = MetricKey.tryParse('a__b:c__d__e:f')!;
      expect(key.base, 'a__b:c__d');
      expect(key.modifiers, [const MetricModifier('e', 'f')]);
    });

    test('a repeated modifier keeps one entry, as upstream does', () {
      // Popped right to left into a dict: the slot is the rightmost
      // occurrence's, the value the leftmost's.
      final key = MetricKey.tryParse('m__k:1__j:2__k:3')!;
      expect(key.modifiers, [
        const MetricModifier('j', '2'),
        const MetricModifier('k', '1'),
      ]);
      expect(key.format(), 'm__j:2__k:1');
    });

    test('a name with no base is refused', () {
      expect(MetricKey.tryParse('a:b'), isNull);
      expect(MetricKey.tryParse('a:b__c:d'), isNull);
    });

    test('value equality', () {
      expect(
        const MetricKey('a', [MetricModifier('k', 'v')]),
        const MetricKey('a', [MetricModifier('k', 'v')]),
      );
      expect(
        const MetricKey('a', [MetricModifier('k', 'v')]),
        isNot(const MetricKey('a', [MetricModifier('k', 'w')])),
      );
      expect(const MetricKey('a'), isNot(const MetricKey('b')));
      expect(
        const MetricKey('a', [MetricModifier('k', 'v')]),
        isNot(const MetricKey('a')),
      );
    });
  });

  group('librelaneMetricsV1', () {
    test('matches upstream library.py row by row', () {
      final file = File('test/fixtures/metrics/library-3.0.16.tsv');
      expect(file.existsSync(), isTrue, reason: 'fixture missing');
      final rows = [
        for (final line in file.readAsLinesSync())
          if (line.isNotEmpty) line.split('\t'),
      ];
      expect(rows, hasLength(61));
      expect(librelaneMetricsV1.definitions, hasLength(rows.length));
      for (final (i, row) in rows.indexed) {
        final d = librelaneMetricsV1.definitions[i];
        expect(d.name, row[0], reason: 'row $i');
        expect(
          switch (d.aggregator) {
            null => 'None',
            final a => '${a.name}_aggregator',
          },
          row[1],
          reason: d.name,
        );
        expect(
          switch (d.higherIsBetter) {
            null => 'None',
            true => 'True',
            false => 'False',
          },
          row[2],
          reason: d.name,
        );
        expect(d.critical ? 'True' : 'None', row[3], reason: d.name);
        expect(
          d.dontAggregate.isEmpty
              ? 'None'
              : "[${d.dontAggregate.map((m) => "'$m'").join(', ')}]",
          row[4],
          reason: d.name,
        );
      }
    });

    test('names its version and source', () {
      expect(librelaneMetricsV1.version, 1);
      expect(librelaneMetricsV1.source, contains('library.py'));
      expect(librelaneMetricsV1.source, contains('3.0.16'));
    });

    test('defines every metric the Flow verdicts and alerts read', () {
      for (final name in [
        'timing__setup__ws',
        'timing__setup__wns',
        'timing__setup__tns',
        'timing__hold__ws',
        'timing__hold__wns',
        'timing__setup_vio__count',
        'timing__hold_vio__count',
        'route__drc_errors',
        'magic__drc_error__count',
        'design__lvs_error__count',
        'route__antenna_violation__count',
        'antenna__violating__nets',
        'design__max_slew_violation__count',
        'design__max_cap_violation__count',
        'design__max_fanout_violation__count',
        'design__instance__utilization',
        'design__instance__area',
        'power__total',
        'ir__drop__worst',
        'design__xor_difference__count',
        'design__inferred_latch__count',
      ]) {
        expect(librelaneMetricsV1.contains(name), isTrue, reason: name);
        expect(librelaneMetricsV1[name]!.name, name);
      }
      expect(librelaneMetricsV1['no__such__metric'], isNull);
    });

    test('definitions have value equality', () {
      expect(
        const MetricDefinition('a', aggregator: MetricAggregator.sum),
        const MetricDefinition('a', aggregator: MetricAggregator.sum),
      );
      expect(
        const MetricDefinition('a', dontAggregate: ['iter']).hashCode,
        const MetricDefinition('a', dontAggregate: ['iter']).hashCode,
      );
      expect(
        const MetricDefinition('a', dontAggregate: ['iter']),
        isNot(const MetricDefinition('a')),
      );
      expect('${librelaneMetricsV1.definitions.first}', contains('area'));
    });
  });

  group('aggregateMetrics', () {
    test("upstream's aggregate_metrics vector", () {
      final vector =
          (_upstreamVectors()['aggregate_metrics']! as List<Object?>).single!
              as Map<String, Object?>;
      final aggregators = vector['aggregators']! as Map<String, Object?>;
      final table = MetricDefinitionTable(
        version: 0,
        source: 'upstream test vector',
        definitions: [
          for (final MapEntry(:key, :value) in aggregators.entries)
            MetricDefinition(
              key,
              aggregator: MetricAggregator.values.byName(value! as String),
            ),
        ],
      );
      final result = aggregateMetrics(
        vector['input']! as Map<String, Object?>,
        table: table,
      );
      final expected = vector['expected']! as Map<String, Object?>;
      expect(result.keys.toSet(), expected.keys.toSet());
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(result[key], value, reason: key);
      }
      // An integer aggregate stays an integer.
      expect(result['flower__count'], isA<int>());
    });

    test('folds into the base and every shorter modifier prefix', () {
      final result = aggregateMetrics({
        'power__total__corner:a__vt:x': 1,
        'power__total__corner:a__vt:y': 2,
        'power__total__corner:b__vt:x': 4,
      });
      expect(result['power__total'], 7);
      expect(result['power__total__corner:a'], 3);
      expect(result['power__total__corner:b'], 4);
      // The input keys stay as they were, first; aggregates follow.
      expect(result.keys.take(3), [
        'power__total__corner:a__vt:x',
        'power__total__corner:a__vt:y',
        'power__total__corner:b__vt:x',
      ]);
    });

    test('min and max follow the definition', () {
      final result = aggregateMetrics({
        'timing__setup__ws__corner:a': 0.5,
        'timing__setup__ws__corner:b': -0.25,
        'ir__drop__worst__net:vdd': 0.01,
        'ir__drop__worst__net:vss': 0.03,
      });
      expect(result['timing__setup__ws'], -0.25);
      expect(result['ir__drop__worst'], 0.03);
    });

    test('arithmetic is decimal, not binary', () {
      final result = aggregateMetrics({
        'power__total__corner:a': 0.1,
        'power__total__corner:b': 0.2,
      });
      expect(result['power__total'], 0.3);
      expect(result['power__total'], isA<double>());
    });

    test('dont_aggregate modifiers are not folded', () {
      final result = aggregateMetrics({
        'route__drc_errors__iter:1': 40,
        'route__drc_errors__iter:2': 3,
        'route__wirelength__iter:1': 100,
      });
      expect(result.containsKey('route__drc_errors'), isFalse);
      expect(result.containsKey('route__wirelength'), isFalse);
    });

    test('an aggregate replaces the unmodified key in place', () {
      final result = aggregateMetrics({
        'timing__hold_vio__count': 99,
        'timing__hold_vio__count__corner:a': 1,
        'timing__hold_vio__count__corner:b': 2,
      });
      expect(result['timing__hold_vio__count'], 3);
      expect(result.keys.first, 'timing__hold_vio__count');
    });

    test('a running zero restarts the fold, as upstream does', () {
      // upstream: `aggregated.get(name) or start`, and 0 is falsy.
      final result = aggregateMetrics({
        'timing__setup__ws__corner:a': 0,
        'timing__setup__ws__corner:b': 5,
      });
      expect(result['timing__setup__ws'], 5);
    });

    test('metrics without an aggregator or definition pass through', () {
      final result = aggregateMetrics({
        'design__instance__utilization__corner:a': 0.5,
        'not__a__metric__corner:a': 1,
        'flow__status': 'done',
      });
      expect(result.containsKey('design__instance__utilization'), isFalse);
      expect(result.containsKey('not__a__metric'), isFalse);
      expect(result['flow__status'], 'done');
    });

    test('non-numbers and malformed keys are skipped', () {
      final result = aggregateMetrics({
        'power__total__corner:a': 'n/a',
        'power__total__corner:b': true,
        'power__total__corner:c': 2,
        'a:b': 1,
      });
      expect(result['power__total'], 2);
    });
  });

  group('MetricsDocument', () {
    test('keeps finite scalars in order', () {
      final doc = MetricsDocument.parse(
        '{"b": 1, "a": 2.5, "s": "x", "n": null, "t": true}',
      );
      expect(doc.values.keys, ['b', 'a', 's', 'n', 't']);
      expect(doc.droppedLongKeys, 0);
      expect(doc.droppedValues, 0);
    });

    test('drops and counts long keys and non-scalar or infinite values', () {
      final long = 'k' * 257;
      final doc = MetricsDocument.parse(
        '{"$long": 1, "${'k' * 256}": 2, "big": 1e999, "obj": {"x": 1}, '
        '"list": [1], "ok": 3}',
      );
      expect(doc.values.keys, ['k' * 256, 'ok']);
      expect(doc.droppedLongKeys, 1);
      expect(doc.droppedValues, 3);
    });

    test('refuses a non-object, malformed or too-deep document', () {
      for (final (text, failure) in [
        ('[1, 2]', FlowReadFailure.malformed),
        ('{"a": ', FlowReadFailure.malformed),
        ('${'[' * 100}${']' * 100}', FlowReadFailure.tooDeep),
      ]) {
        expect(
          () => MetricsDocument.parse(text),
          throwsA(
            isA<FlowReadException>().having(
              (e) => e.failure,
              'failure',
              failure,
            ),
          ),
          reason: text,
        );
      }
    });

    test('refuses a document over the byte cap', () {
      expect(
        () => MetricsDocument.parse(
          '{"a": 1}',
          limits: const FlowInputLimits(maxBytes: 4),
        ),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.tooLarge,
          ),
        ),
      );
    });

    test('reads a file, and an absent file is a file-system error', () async {
      final dir = await Directory.systemTemp.createTemp('crux_flow_metrics');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/metrics.json')
        ..writeAsStringSync('{"power__total": 0.5}');
      final doc = await MetricsDocument.readFile(file.path);
      expect(doc.values, {'power__total': 0.5});
      await expectLater(
        MetricsDocument.readFile('${dir.path}/absent.json'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        MetricsDocument.readFile(
          file.path,
          limits: const FlowInputLimits(maxBytes: 3),
        ),
        throwsA(isA<FlowReadException>()),
      );
    });

    test('refuses bytes that are not UTF-8 when read from disk', () async {
      final dir = await Directory.systemTemp.createTemp('crux_flow_metrics');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/metrics.json')
        ..writeAsBytesSync([0x7B, 0xFF, 0xFE, 0x7D]);
      await expectLater(
        MetricsDocument.readFile(file.path),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.malformed,
          ),
        ),
      );
    });
  });
}
