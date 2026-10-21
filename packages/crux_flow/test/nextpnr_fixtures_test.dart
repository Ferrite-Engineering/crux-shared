// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

/// Every captured place-and-route case. Listed here rather than discovered,
/// so a lost case directory fails instead of shrinking the loop.
const _cases = [
  'rescreen_ice40',
  'rescreen_ice40_dsp',
  'rescreen_ecp5',
  'path_ice40_met',
  'path_ice40_violated',
  'path_ecp5_met',
  'path_ecp5_violated',
  'path_gowin_met',
  'path_gowin_violated',
  'path_gatemate_met',
  'path_gatemate_violated',
];

const _root = 'test/fixtures/nextpnr';

Map<String, Object?> _expected(String dir) {
  final file = File('$dir/verdict.expected.json');
  expect(file.existsSync(), isTrue, reason: '${file.path} missing');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

FlowVerdict _verdict(Map<String, Object?> expected) =>
    FlowVerdict.fromWireName(expected['verdict']! as String);

void main() {
  test('the fixture set is complete', () {
    expect(Directory(_root).existsSync(), isTrue, reason: '$_root missing');
    final present = Directory(_root)
        .listSync()
        .whereType<Directory>()
        .map((d) => d.uri.pathSegments.reversed.skip(1).first)
        .where((name) => name != 'rtl')
        .toSet();
    expect(present, _cases.toSet());
    for (final name in _cases) {
      for (final file in ['report.json', 'pnr.log', 'verdict.expected.json']) {
        expect(
          File('$_root/$name/$file').existsSync(),
          isTrue,
          reason: '$name/$file',
        );
      }
    }
  });

  group('both readers agree with nextpnr on every case', () {
    for (final name in _cases) {
      test(name, () async {
        final dir = '$_root/$name';
        final expected = _expected(dir);
        final verdict = _verdict(expected);
        final constraint = (expected['constraint_mhz']! as num).toDouble();

        final report = await const NextpnrReportReader().readFile(
          '$dir/report.json',
        );
        final log = await const NextpnrLogReader().readFile('$dir/pnr.log');

        expect(report.verdict, verdict, reason: 'report');
        expect(log.verdict, verdict, reason: 'log');

        final reportClocks = report.result!.clocks;
        final logClocks = log.result!.clocks;
        expect(reportClocks, isNotEmpty);
        expect(
          logClocks.map((c) => c.clock),
          reportClocks.map((c) => c.clock),
        );
        for (final (i, fromReport) in reportClocks.indexed) {
          final fromLog = logClocks[i];
          expect(fromReport.constraintMhz, constraint);
          expect(fromLog.constraintMhz, constraint);
          expect(fromLog.logMarker, expected['marker']);
          expect(fromReport.logMarker, isNull);
          // The log prints the report's figure to two decimals.
          expect(fromLog.achievedMhz, closeTo(fromReport.achievedMhz, 0.006));
        }

        // nextpnr's own exit status agrees: 0 when met, 1 when violated.
        final exitCode = int.parse(
          File('$dir/exit_code.txt').readAsStringSync().trim(),
        );
        expect(exitCode, expected['exit_code']);
        expect(exitCode == 0, verdict == FlowVerdict.met);
      });
    }
  });

  group('the report reads every family', () {
    for (final name in _cases) {
      test('$name: critical paths', () async {
        final report = (await const NextpnrReportReader().readFile(
          '$_root/$name/report.json',
        )).result!;
        expect(report.criticalPaths, isNotEmpty);
        expect(report.utilization, isNotEmpty);
        for (final (i, path) in report.criticalPaths.indexed) {
          expect(path.rank, i + 1);
          expect(path.origin, TimingPathOrigin.nextpnrReport);
          expect(path.segments, isNotEmpty);
          expect(path.startpoint, path.segments.first.fromCell);
          expect(path.endpoint, path.segments.last.toCell);
          expect(
            path.delayPs,
            closeTo(path.segments.fold<int>(0, (s, x) => s + x.delayPs), 50),
          );
        }
        // The first path is register to register on the one clock, and its
        // delay is the clock's achieved period.
        final first = report.criticalPaths.first;
        final clock = report.clocks.single;
        expect(first.clockFrom, clock.clock);
        expect(first.clockTo, clock.clock);
        expect(first.fromEdge, ClockEdge.rising);
        expect(
          1e6 / first.delayPs,
          closeTo(clock.achievedMhz, clock.achievedMhz * 0.005),
        );
      });
    }

    test('GateMate keeps its clk-skew segments, Gowin has no source', () async {
      Future<Set<String>> rawTypes(String name) async {
        final report = (await const NextpnrReportReader().readFile(
          '$_root/$name/report.json',
        )).result!;
        return {
          for (final p in report.criticalPaths)
            for (final s in p.segments) s.rawType,
        };
      }

      final gatemate = await rawTypes('path_gatemate_met');
      expect(gatemate, contains('clk-skew'));
      final gowin = await rawTypes('path_gowin_met');
      expect(gowin, isNot(contains('source')));
      expect(await rawTypes('path_ice40_met'), contains('source'));
    });

    test('designed paths end at the register the RTL names', () async {
      final mapping =
          jsonDecode(
                File('$_root/mapping.expected.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final cases = mapping['cases']! as Map<String, Object?>;
      final endRegister = mapping['end_register']! as String;
      final starts = (mapping['start_registers']! as List<Object?>)
          .cast<String>();
      for (final MapEntry(:key, :value) in cases.entries) {
        final carries =
            (value! as Map<String, Object?>)['cell_names_carry_register']!
                as bool;
        final first = (await const NextpnrReportReader().readFile(
          '$_root/$key/report.json',
        )).result!.criticalPaths.first;
        if (carries) {
          expect(first.endpoint, startsWith(endRegister), reason: key);
          expect(
            starts.any(first.startpoint.startsWith),
            isTrue,
            reason: key,
          );
        } else {
          // Opaque cell names: the register shows only in net names and
          // source spans along the path.
          expect(first.endpoint, isNot(startsWith(endRegister)), reason: key);
          final nets = first.segments.map((s) => s.net).whereType<String>();
          expect(nets.any((n) => starts.any(n.startsWith)), isTrue);
          final spans = first.segments
              .expand((s) => s.sources)
              .expand(
                SrcSpan.parseAll,
              );
          expect(
            spans.any(
              (s) =>
                  s.file == 'path_adder.v' &&
                  s.startLine == mapping['path_statement_line'],
            ),
            isTrue,
          );
        }
      }
    });
  });

  test('the FuseSoC run without --report reads from its log alone', () async {
    const dir = 'test/fixtures/fusesoc';
    final expected = _expected(dir);
    expect(expected['report_json_present'], isFalse);
    expect(File('$dir/report.json').existsSync(), isFalse);

    final missing = await const NextpnrReportReader().readFile(
      '$dir/report.json',
    );
    expect(missing.verdict, FlowVerdict.notRun);
    expect(missing.result, isNull);
    expect(missing.problem, isNotNull);

    final log = await const NextpnrLogReader().readFile('$dir/next.log');
    expect(log.verdict, _verdict(expected));
    final clock = log.result!.clocks.single;
    expect(clock.logMarker, expected['marker']);
    expect(clock.constraintMhz, expected['constraint_mhz']);
    expect(log.result!.errorLine, isNull);
  });
}
