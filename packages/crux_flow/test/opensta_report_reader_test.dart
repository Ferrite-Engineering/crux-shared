// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

const _sta = '55-openroad-stapostpnr/nom_tt_025C_1v80';

String _listing(String version, String name, String file) =>
    'test/fixtures/librelane/$version/$name/run/$_sta/$file';

/// Every path's slack, read independently: the number before
/// `slack (MET)` or `slack (VIOLATED)`.
List<double> _slacks(String text) => [
  for (final m in RegExp(
    r'^\s*(-?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)',
    multiLine: true,
  ).allMatches(text))
    double.parse(m.group(1)!),
];

void main() {
  final listings = [
    ('3.0.16', 'sky130A_met', 'max.rpt', OpenStaPathDelay.max),
    ('3.0.16', 'sky130A_met', 'min.rpt', OpenStaPathDelay.min),
    ('3.0.16', 'sky130A_timing', 'max.rpt', OpenStaPathDelay.max),
    ('3.0.15', 'sky130A_met', 'max.rpt', OpenStaPathDelay.max),
  ];

  for (final (version, name, file, delay) in listings) {
    test('$version $name $file: every path read, worst first', () async {
      final path = _listing(version, name, file);
      expect(File(path).existsSync(), isTrue, reason: '$path missing');
      final text = File(path).readAsStringSync();
      final slacks = _slacks(text)..sort();
      final report = await const OpenStaReportReader(
        maxPaths: 1000,
      ).readFile(path);
      expect(report.corner, 'nom_tt_025C_1v80');
      expect(report.pathDelay, delay);
      expect(report.skipped, 0);
      expect(report.pathCount, slacks.length);
      expect(report.paths, hasLength(slacks.length));
      for (final (i, path) in report.paths.indexed) {
        expect(path.rank, i + 1);
        expect(path.slackPs, (slacks[i] * 1000).round());
        expect(path.origin, TimingPathOrigin.openSta);
        expect(path.segments, isNotEmpty);
      }
      // A register-to-register path opens with clk-to-q and closes with the
      // library's check.
      final regToReg = report.paths.firstWhere(
        (t) => t.segments.first.type == TimingSegmentType.clkToQ,
      );
      expect(regToReg.clockFrom, 'clk');
      expect(regToReg.fromEdge, ClockEdge.rising);
      expect(
        regToReg.segments.last.type,
        delay == OpenStaPathDelay.max
            ? TimingSegmentType.setup
            : TimingSegmentType.hold,
      );
      expect(regToReg.segments.last.toCell, regToReg.endpoint);
      // Every routing segment names its net.
      for (final s in regToReg.segments) {
        if (s.type == TimingSegmentType.routing) expect(s.net, isNotNull);
      }
    });
  }

  test('the worst path of the timing case, exactly as listed', () async {
    final report = await const OpenStaReportReader().readFile(
      _listing('3.0.16', 'sky130A_timing', 'max.rpt'),
    );
    final worst = report.paths.first;
    // The listing's first block: _354_ to _400_, slack -0.903735.
    expect(worst.startpoint, '_354_');
    expect(worst.endpoint, '_400_');
    expect(worst.slackPs, -904);
    expect(worst.delayNs, closeTo(2.997054, 1e-9));
    final first = worst.segments.first;
    expect(
      (first.rawType, first.fromCell, first.toCell, first.toPort),
      ('clk-to-q', '_354_', '_354_', 'Q'),
    );
    expect(first.delayNs, closeTo(0.383358, 1e-9));
    final second = worst.segments[1];
    expect(
      (second.rawType, second.net, second.toCell),
      (
        'routing',
        'src_b[1]',
        '_166_',
      ),
    );
    final setup = worst.segments.last;
    expect(setup.type, TimingSegmentType.setup);
    expect(setup.delayNs, closeTo(0.071369, 1e-9));
  });

  test('maxPaths keeps the worst few', () async {
    final report = await const OpenStaReportReader(maxPaths: 3).readFile(
      _listing('3.0.16', 'sky130A_timing', 'max.rpt'),
    );
    expect(report.paths, hasLength(3));
    expect(report.pathCount, greaterThan(3));
    expect(report.paths.map((t) => t.endpoint), ['_400_', '_399_', '_401_']);
  });

  test('equal slacks keep the listing order', () {
    String block(String end, String slack) =>
        'Startpoint: a (input port clocked by clk)\n'
        'Endpoint: $end (output port clocked by clk)\n'
        'Path Group: clk\nPath Type: max\n\n'
        'Fanout Cap Slew Delay Time Description\n'
        '---\n'
        '  0.0 0.0 clock clk (rise edge)\n'
        '  0.1 0.1 ^ a (in)\n'
        '  a (net)\n'
        '  0.2 0.3 ^ $end (out)\n'
        '  0.3 data arrival time\n'
        '---\n'
        '  $slack slack (MET)\n\n';
    final report = const OpenStaReportReader().parse(
      block('x', '1.000000') + block('y', '0.500000') + block('z', '1.000000'),
    );
    expect(report.paths.map((t) => t.endpoint), ['y', 'x', 'z']);
    expect(report.paths.first.segments.single.type, TimingSegmentType.routing);
  });

  test('a block without a slack line is skipped and counted', () {
    final report = const OpenStaReportReader().parse(
      'Startpoint: a (input port)\nEndpoint: b (output port)\n'
      'Fanout\n  0.1 0.1 ^ a (in)\n',
    );
    expect((report.pathCount, report.skipped), (1, 1));
    expect(report.paths, isEmpty);
  });

  test('over the byte cap is refused', () {
    expect(
      () => const OpenStaReportReader(
        limits: FlowInputLimits(maxBytes: 10),
      ).parse('Startpoint: ${'x' * 20}'),
      throwsA(
        isA<FlowReadException>().having(
          (e) => e.failure,
          'failure',
          FlowReadFailure.tooLarge,
        ),
      ),
    );
  });

  test('an empty listing (a trimmed corner) reads as no paths', () {
    final report = const OpenStaReportReader().parse('');
    expect(report.pathCount, 0);
    expect(report.paths, isEmpty);
    expect(report.pathDelay, isNull);
  });
}
