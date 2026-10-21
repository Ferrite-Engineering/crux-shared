// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

String _report({
  Map<String, Object?>? fmax,
  List<Object?>? paths,
  Map<String, Object?>? utilization,
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'fmax':
      fmax ??
      {
        'clk': {'achieved': 120.5, 'constraint': 100},
      },
  'critical_paths': ?paths,
  'utilization': ?utilization,
  ...extra,
});

Map<String, Object?> _step(
  String type,
  double delay, {
  String from = 'a',
  String to = 'b',
  String? net,
  List<String>? sources,
}) => {
  'type': type,
  'delay': delay,
  'from': {
    'cell': from,
    'port': 'Q',
    'loc': [1, 2],
  },
  'to': {'cell': to, 'port': 'D'},
  'net': ?net,
  'sources': ?sources,
};

void main() {
  const reader = NextpnrReportReader();
  const logReader = NextpnrLogReader();

  group('NextpnrReportReader', () {
    test('met iff every clock reaches its constraint', () {
      expect(reader.parse(_report()).verdict, FlowVerdict.met);
      expect(
        reader
            .parse(
              _report(
                fmax: {
                  'a': {'achieved': 100, 'constraint': 100},
                  'b': {'achieved': 99.99, 'constraint': 100},
                },
              ),
            )
            .verdict,
        FlowVerdict.violated,
      );
      expect(
        reader
            .parse(
              _report(
                fmax: {
                  'a': {'achieved': 100.0, 'constraint': 100},
                },
              ),
            )
            .verdict,
        FlowVerdict.met,
        reason: 'equal is met',
      );
    });

    test('no clocks is unrecognised, never a vacuous met', () {
      expect(
        reader.parse(_report(fmax: {})).verdict,
        FlowVerdict.unrecognised,
      );
    });

    test('reads a path: events, cells, ports, nets, spans, delays', () {
      final report = reader.parse(
        _report(
          paths: [
            {
              'from': 'negedge clk',
              'to': '<async>',
              'path': [
                _step('clk-to-q', 0.5, from: 'r1', to: 'r1'),
                _step(
                  'routing',
                  1.25,
                  from: 'r1',
                  to: 'lut',
                  net: 'n1',
                  sources: ['top.v:3.1-3.9', 'top.v:4'],
                ),
                _step('a-new-kind', 0.0004, from: 'lut', to: 'out'),
              ],
            },
          ],
          utilization: {
            'LUT4': {'available': 5280, 'used': 12},
          },
        ),
      );
      final path = report.criticalPaths.single;
      expect(path.rank, 1);
      expect(path.clockFrom, 'clk');
      expect(path.fromEdge, ClockEdge.falling);
      expect(path.clockTo, isNull);
      expect(path.toEdge, isNull);
      expect(path.startpoint, 'r1');
      expect(path.endpoint, 'out');
      expect(path.slackPs, isNull);
      expect(path.delayNs, closeTo(1.7504, 1e-12));
      expect(path.delayPs, 1750);
      final routing = path.segments[1];
      expect(routing.type, TimingSegmentType.routing);
      expect(routing.net, 'n1');
      expect(routing.fromPort, 'Q');
      expect(routing.toPort, 'D');
      expect(routing.delayPs, 1250);
      expect(routing.delayNs, 1.25);
      expect(routing.sources, ['top.v:3.1-3.9', 'top.v:4']);
      expect(path.segments.last.type, TimingSegmentType.other);
      expect(path.segments.last.rawType, 'a-new-kind');
      expect(path.segments.last.delayPs, 0);
      expect(
        report.utilization['LUT4'],
        const NextpnrResourceUse(used: 12, available: 5280),
      );
      expect('${report.utilization['LUT4']}', contains('12'));
    });

    test('an event that is not an edge keeps its text as the clock', () {
      final path = reader
          .parse(
            _report(
              paths: [
                {
                  'from': 'clk',
                  'to': 'posedge clk2',
                  'path': [_step('logic', 1)],
                },
              ],
            ),
          )
          .criticalPaths
          .single;
      expect(path.clockFrom, 'clk');
      expect(path.fromEdge, isNull);
      expect(path.clockTo, 'clk2');
      expect(path.toEdge, ClockEdge.rising);
    });

    test('unknown keys are ignored', () {
      expect(
        reader
            .parse(
              _report(
                extra: {
                  'detailed_net_timings': [
                    {'anything': true},
                  ],
                  'future_section': {'x': 1},
                },
              ),
            )
            .clocks
            .single
            .clock,
        'clk',
      );
    });

    final malformed = <String, String>{
      'not JSON': '{"fmax": ',
      'not an object': '[1]',
      'no fmax': '{}',
      'fmax entry not an object': '{"fmax": {"clk": 3}}',
      'achieved missing': '{"fmax": {"clk": {"constraint": 12}}}',
      'achieved a string':
          '{"fmax": {"clk": {"achieved": "1", "constraint": 1}}}',
      'path with no segments': _report(
        paths: [
          {'from': '<async>', 'to': '<async>', 'path': <Object?>[]},
        ],
      ),
      'segment without a cell': _report(
        paths: [
          {
            'from': '<async>',
            'to': '<async>',
            'path': [
              {
                'type': 'logic',
                'delay': 1,
                'from': <String, Object?>{},
                'to': {'cell': 'b'},
              },
            ],
          },
        ],
      ),
      'sources not strings': _report(
        paths: [
          {
            'from': '<async>',
            'to': '<async>',
            'path': [
              {
                ..._step('routing', 1),
                'sources': [1],
              },
            ],
          },
        ],
      ),
      'utilization not integers': _report(
        utilization: {
          'LUT4': {'available': 'many', 'used': 1},
        },
      ),
    };
    for (final MapEntry(:key, :value) in malformed.entries) {
      test('refuses: $key', () {
        expect(() => reader.parse(value), throwsA(isA<FlowReadException>()));
      });
    }

    test('refuses a number that decodes to infinity', () {
      expect(
        () => reader.parse(
          _report().replaceFirst('"constraint":100', '"constraint":1e999'),
        ),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.nonFinite,
          ),
        ),
      );
    });

    test('refuses a delay too large to be a time', () {
      expect(
        () => reader.parse(
          _report(
            paths: [
              {
                'from': '<async>',
                'to': '<async>',
                'path': [_step('logic', 10000000000000)],
              },
            ],
          ),
        ),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.nonFinite,
          ),
        ),
      );
    });

    test('refuses JSON nested past the depth cap', () {
      final deep = '{"fmax": {}, "x": ${'[' * 65}${']' * 65}}';
      expect(
        () => reader.parse(deep),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.tooDeep,
          ),
        ),
      );
      // Brackets inside strings do not count.
      expect(
        reader.parse(_report(extra: {'note': '[[[[[[[[' * 20})).verdict,
        FlowVerdict.met,
      );
    });

    group('readFile', () {
      late Directory dir;
      setUp(() async {
        dir = await Directory.systemTemp.createTemp('crux_flow_nextpnr');
      });
      tearDown(() => dir.delete(recursive: true));

      test('absent is not run', () async {
        final r = await reader.readFile('${dir.path}/report.json');
        expect(r.verdict, FlowVerdict.notRun);
        expect(r.result, isNull);
      });

      test('malformed is unrecognised', () async {
        final f = File('${dir.path}/report.json')..writeAsStringSync('{');
        final r = await reader.readFile(f.path);
        expect(r.verdict, FlowVerdict.unrecognised);
        expect(r.problem, isNotNull);
      });

      test('over the byte cap is unrecognised, unread', () async {
        final f = File('${dir.path}/report.json')..writeAsStringSync(_report());
        final r = await const NextpnrReportReader(
          limits: FlowInputLimits(maxBytes: 10),
        ).readFile(f.path);
        expect(r.verdict, FlowVerdict.unrecognised);
        expect(r.problem, contains('over the cap'));
      });

      test('a directory where the file should be is not run', () async {
        final r = await reader.readFile(dir.path);
        expect(r.verdict, FlowVerdict.notRun);
      });

      test('not UTF-8 is unrecognised', () async {
        final f = File('${dir.path}/report.json')
          ..writeAsBytesSync([0x7B, 0xC3, 0x28, 0x7D]);
        expect(
          (await reader.readFile(f.path)).verdict,
          FlowVerdict.unrecognised,
        );
      });
    });
  });

  group('NextpnrLogReader', () {
    const pass =
        "Info: Max frequency for clock 'clk': 61.52 MHz (PASS at 12.00 MHz)";
    const fail =
        "ERROR: Max frequency for clock 'clk': 60.91 MHz (FAIL at 100.00 MHz)";

    test('the last line per clock is the result', () {
      final log = logReader.parse('$pass\nInfo: routing\n$fail\n');
      expect(log.clocks.single.logMarker, 'FAIL');
      expect(log.clocks.single.achievedMhz, 60.91);
      expect(log.clocks.single.constraintMhz, 100);
      expect(log.verdict, FlowVerdict.violated);
      expect(log.errorLine, isNull, reason: 'a timing ERROR is not a stop');
    });

    test('the marker decides, not the rounded figures', () {
      final log = logReader.parse(
        "Info: Max frequency for clock 'c': 12.00 MHz (FAIL at 12.00 MHz)",
      );
      expect(log.clocks.single.meetsConstraint, isFalse);
      expect(log.verdict, FlowVerdict.violated);
    });

    test('several clocks keep their first-seen order', () {
      final log = logReader.parse(
        "Info: Max frequency for clock 'b': 50.00 MHz (PASS at 10.00 MHz)\n"
        "Info: Max frequency for clock 'a': 50.00 MHz (PASS at 10.00 MHz)\n"
        "Warning: Max frequency for clock 'b': 40.00 MHz (PASS at 10.00 MHz)\n",
      );
      expect(log.clocks.map((c) => c.clock), ['b', 'a']);
      expect(log.clocks.first.achievedMhz, 40);
      expect(log.verdict, FlowVerdict.met);
    });

    test('a clock name with spaces and quotes', () {
      final log = logReader.parse(
        "Info: Max frequency for clock 'u0.clk 'x'': 50.00 MHz "
        '(PASS at 10.00 MHz)',
      );
      expect(log.clocks.single.clock, "u0.clk 'x'");
    });

    test('an error before any timing result is stopped', () {
      final log = logReader.parse(
        'Info: Packing design\nERROR: Unable to place cell x\n',
      );
      expect(log.verdict, FlowVerdict.stopped);
      expect(log.errorLine, 'ERROR: Unable to place cell x');
    });

    test('neither timing nor an error is unrecognised', () {
      expect(logReader.parse('').verdict, FlowVerdict.unrecognised);
      expect(
        logReader.parse('Info: Program finished normally.\n').verdict,
        FlowVerdict.unrecognised,
      );
    });

    test('lines over the cap are skipped, not parsed', () {
      final long = '$pass${' ' * 100}';
      final log = const NextpnrLogReader(
        limits: FlowInputLimits(maxLineLength: 80),
      ).parse(long);
      expect(log.clocks, isEmpty);
    });

    test('a whole log over the cap is refused', () {
      expect(
        () => const NextpnrLogReader(
          limits: FlowInputLimits(maxBytes: 10),
        ).parse(pass),
        throwsA(isA<FlowReadException>()),
      );
    });

    test('lookalike lines are not results', () {
      for (final line in [
        "Info: Max frequency for clock 'clk': fast MHz (PASS at 12.00 MHz)",
        "Info: Max frequency for clock 'clk': 61.52 MHz (OK at 12.00 MHz)",
        "Max frequency for clock 'clk': 61.52 MHz (PASS at 12.00 MHz)",
        'Info: Max delay <async> -> posedge clk: 6.13 ns',
      ]) {
        expect(logReader.parse(line).clocks, isEmpty, reason: line);
      }
    });

    test('readFile: absent is not run, too large unrecognised', () async {
      final dir = await Directory.systemTemp.createTemp('crux_flow_log');
      addTearDown(() => dir.delete(recursive: true));
      expect(
        (await logReader.readFile('${dir.path}/pnr.log')).verdict,
        FlowVerdict.notRun,
      );
      final f = File('${dir.path}/pnr.log')..writeAsStringSync(pass);
      expect((await logReader.readFile(f.path)).verdict, FlowVerdict.met);
      expect(
        (await const NextpnrLogReader(
          limits: FlowInputLimits(maxBytes: 4),
        ).readFile(f.path)).verdict,
        FlowVerdict.unrecognised,
      );
    });
  });

  test('clock results have value equality', () {
    const a = NextpnrClockFrequency(
      clock: 'c',
      achievedMhz: 1,
      constraintMhz: 2,
      logMarker: 'FAIL',
    );
    expect(
      a,
      const NextpnrClockFrequency(
        clock: 'c',
        achievedMhz: 1,
        constraintMhz: 2,
        logMarker: 'FAIL',
      ),
    );
    expect(a.hashCode, isNot(0));
    expect('$a', contains('c'));
    expect(
      const NextpnrClockFrequency(
        clock: 'c',
        achievedMhz: 3,
        constraintMhz: 2,
      ).meetsConstraint,
      isTrue,
    );
  });
}
