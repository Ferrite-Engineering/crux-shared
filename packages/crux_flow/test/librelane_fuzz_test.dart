// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crux_flow/crux_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _run = 'test/fixtures/librelane/3.0.16/sky130A_timing/run';

List<String> _mutants(String seed, Random random, int count) {
  const junk = [
    '[',
    '{',
    ']',
    '}',
    '"',
    r'\',
    ':',
    ',',
    '1e999',
    '-1e999',
    'null',
    'Startpoint: ',
    'slack (MET)',
    'data arrival time',
    '(net)',
    '^ x (y)',
    "Running '",
    "Skipping step '",
    '\u0000',
    '\n',
    '-',
    '--------',
  ];
  String splice(String s, String insert) {
    final at = random.nextInt(s.length + 1);
    return '${s.substring(0, at)}$insert${s.substring(at)}';
  }

  return [
    for (var i = 0; i < count; i++)
      switch (random.nextInt(5)) {
        0 => seed.substring(0, random.nextInt(seed.length + 1)),
        1 => splice(seed, junk[random.nextInt(junk.length)]),
        2 => splice(seed, '[' * (60 + random.nextInt(100))),
        3 => String.fromCharCodes(
          List.generate(random.nextInt(200), (_) => random.nextInt(0x7F)),
        ),
        _ => splice(
          splice(seed, junk[random.nextInt(junk.length)]),
          junk[random.nextInt(junk.length)],
        ),
      },
  ];
}

String _corner(Random random) =>
    random.nextBool() ? '__corner:c${random.nextInt(3)}' : '';

void _onlyReadErrors(String input, void Function() body) {
  try {
    body();
  } on FlowReadException {
    // The documented failure.
  } on Object catch (e) {
    fail('${e.runtimeType} escaped on input of ${input.length} chars: $e');
  }
}

void main() {
  final random = Random(6);

  test('OpenStaReportReader: only FlowReadException escapes', () {
    final seed = File(
      p.join(_run, '55-openroad-stapostpnr/nom_tt_025C_1v80/max.rpt'),
    ).readAsStringSync().substring(0, 20000);
    for (final input in _mutants(seed, random, 300)) {
      _onlyReadErrors(input, () {
        final report = const OpenStaReportReader().parse(input);
        for (final path in report.paths) {
          expect(path.slackPs, isNotNull);
        }
      });
    }
  });

  test('OpenStaReportReader: huge numbers and long lines are bounded', () {
    final report =
        const OpenStaReportReader(
          limits: FlowInputLimits(maxLineLength: 100),
        ).parse(
          'Startpoint: a (input port)\nEndpoint: b (output port)\nFanout\n'
          '  1e300 1e300 ^ a (in)\n${'x' * 200}\n  ${'9' * 400} slack (MET)\n',
        );
    // 1e300 ns is not a representable delay: the path is not kept.
    expect(report.paths, isEmpty);
  }, skip: false);

  test('LibreLaneFlowLog: never throws', () {
    final seed = File(p.join(_run, 'flow.log')).readAsStringSync();
    for (final input in _mutants(seed, random, 300)) {
      LibreLaneFlowLog.parse(input, maxLineLength: 512);
    }
  });

  test('LibreLaneMetricsReader.parseCsv: only FlowReadException escapes', () {
    final seed = File(
      p.join(_run, 'final/metrics.csv'),
    ).readAsStringSync().substring(0, 4000);
    for (final input in _mutants(seed, random, 300)) {
      _onlyReadErrors(
        input,
        () => const LibreLaneMetricsReader().parseCsv(input),
      );
    }
  });

  test('metric keys over the length cap are dropped and counted', () {
    final doc = const LibreLaneMetricsReader(
      limits: FlowInputLimits(maxMetricKeyLength: 8),
    ).parseCsv('Metric,Value\nshort,1\n${'k' * 20},2\nnan,1e999\n');
    expect(doc.values, {'short': 1, 'nan': '1e999'});
    expect(doc.droppedLongKeys, 1);
  });

  test('evaluateLibreLaneChecks: hostile values never throw', () {
    final values = <Object?>[
      null,
      'x',
      true,
      -1,
      0,
      1,
      1.5,
      double.nan,
      double.infinity,
      <Object?>[],
      <String, Object?>{},
    ];
    for (var i = 0; i < 500; i++) {
      final metrics = <String, Object?>{
        for (final check in kLibreLane30Checks)
          if (random.nextBool())
            check.metric + _corner(random):
                values[random.nextInt(values.length)],
      };
      final config = <String, Object?>{
        'TIMING_VIOLATION_CORNERS': values[random.nextInt(values.length)],
        'SETUP_VIOLATION_CORNERS': random.nextBool() ? ['[', '*', '!c1'] : 3,
        'ERROR_ON_TR_DRC': values[random.nextInt(values.length)],
        'WIRE_LENGTH_THRESHOLD': values[random.nextInt(values.length)],
      };
      evaluateLibreLaneChecks(metrics, config);
    }
  });

  test('NextpnrReportReader.parseNetTimings: only FlowReadException '
      'escapes', () {
    const seed =
        '{"detailed_net_timings": [{"net": "n", "driver": "c", "port": "Q",'
        ' "sources": ["a.v:1.1-1.2"], "endpoints": [{"cell": "d", '
        '"port": "D", "event": "r", "delay": [0.1, 0.2]}]}]}';
    for (final input in _mutants(seed, random, 300)) {
      _onlyReadErrors(
        input,
        () => const NextpnrReportReader().parseNetTimings(input),
      );
    }
  });

  test(
    'a run root of junk files and odd names reads without throwing',
    () async {
      final temp = Directory.systemTemp.createTempSync('crux_flow_fuzz_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final root = temp.resolveSymbolicLinksSync();
      for (final name in ['1-a', '02-b..c', 'x-1', '999999999999999999999-z']) {
        Directory(p.join(root, name)).createSync();
      }
      File(p.join(root, '1-a', 'runtime.txt')).writeAsStringSync('99:99');
      File(p.join(root, '1-a', 'state_out.json')).writeAsStringSync('');
      File(p.join(root, 'resolved.json')).writeAsStringSync(
        jsonEncode({
          'meta': {'librelane_version': '3.0.16'},
          'DESIGN_NAME': '../../etc',
          'CLOCK_PERIOD': 'x',
        }),
      );
      Directory(p.join(root, 'final')).createSync();
      File(p.join(root, 'final', 'metrics.json')).writeAsStringSync('{"a": 1}');
      final reading = await LibreLaneReaders.standard().read(root);
      // `02-b..c` has no output state and final metrics exist: a deferred
      // failure, by the records.
      expect(reading.verdict, FlowVerdict.violated);
      expect(reading.run.steps.map((s) => s.dir), ['1-a', '02-b..c']);
      expect(reading.run.steps.first.runtime, isNull);
      expect(reading.run.artifacts.containsKey('gds'), isFalse);
      expect(reading.clockPeriodNs, isNull);
    },
  );
}
