// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _root = 'test/fixtures/librelane';

/// Every case of the fixture set, by release. A missing directory fails.
const Map<String, List<String>> _cases = {
  '3.0.17': ['sky130A_met'],
  '3.0.16': [
    'sky130A_met',
    'sky130A_timing',
    'sky130A_drc',
    'sky130A_antenna',
    'sky130A_stopped',
    'gf180mcuD_met',
    'ihp-sg13g2_met',
  ],
  '3.0.15': ['sky130A_met'],
};

String _run(String version, String name) =>
    p.normalize(Directory('$_root/$version/$name/run').absolute.path);

Map<String, Object?> _expected(String version, String name) =>
    jsonDecode(
          File('$_root/$version/$name/case.expected.json').readAsStringSync(),
        )
        as Map<String, Object?>;

/// A copy of [source] under a fresh temporary directory, for the cases that
/// alter a run.
Directory _copy(String source) {
  final temp = Directory.systemTemp.createTempSync('crux_flow_ll_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final target = Directory(p.join(temp.path, p.basename(source)))..createSync();
  for (final entity in Directory(source).listSync(recursive: true)) {
    final rel = p.relative(entity.path, from: source);
    if (entity is Directory) {
      Directory(p.join(target.path, rel)).createSync(recursive: true);
    } else if (entity is File) {
      File(p.join(target.path, rel))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
  return Directory(target.resolveSymbolicLinksSync());
}

void main() {
  group('LibreLaneVersion', () {
    test('parses releases and orders them by number', () {
      final v = LibreLaneVersion.tryParse('3.0.16')!;
      expect((v.major, v.minor, v.patch, v.line), (3, 0, 16, '3.0'));
      expect(v.isRelease, isTrue);
      expect(LibreLaneVersion.tryParse('3.0.17.dev4')!.isRelease, isFalse);
      expect(LibreLaneVersion.tryParse('2.3')!.patch, 0);
      expect(
        LibreLaneVersion.tryParse('3.0.9')!.compareTo(
          LibreLaneVersion.tryParse('3.0.16')!,
        ),
        lessThan(0),
      );
      for (final bad in [null, '', 'x', '3', 'v', '3.x.1', 'a' * 65]) {
        expect(LibreLaneVersion.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('the 3.0 reader is verified for exactly 3.0.15 to 3.0.17', () {
      expect(kLibreLane30Verified.first.raw, '3.0.15');
      expect(kLibreLane30Verified.last.raw, '3.0.17');
      bool verified(String v) =>
          kLibreLane30Verified.contains(LibreLaneVersion.tryParse(v)!);
      expect(verified('3.0.15'), isTrue);
      expect(verified('3.0.16'), isTrue);
      expect(verified('3.0.17'), isTrue);
      for (final v in [
        '3.0.14',
        '3.0.18',
        '3.0.16.dev1',
        '3.0.17.dev4',
        '3.1.0',
        '2.3.9',
      ]) {
        expect(verified(v), isFalse, reason: v);
      }
    });
  });

  group('LibreLaneReaders.select', () {
    final readers = LibreLaneReaders.standard();
    (String, bool) pick(String? v) {
      final (reader, verified) = readers.select(
        v == null ? null : LibreLaneVersion.tryParse(v),
      );
      return (reader.line, verified);
    }

    test('a verified release selects its line, verified', () {
      expect(pick('3.0.15'), ('3.0', true));
      expect(pick('3.0.16'), ('3.0', true));
      expect(pick('3.0.17'), ('3.0', true));
    });

    test('anything else selects the nearest older reader, unverified', () {
      expect(pick('3.0.18'), ('3.0', false));
      expect(pick('3.1.0'), ('3.0', false));
      expect(pick('4.0.0'), ('3.0', false));
      // Older than every line: the oldest reader.
      expect(pick('2.3.9'), ('3.0', false));
      expect(pick(null), ('3.0', false));
    });

    test('with two lines, a release between them takes the older', () {
      final two = LibreLaneReaders(<LibreLaneRunReader>[
        const LibreLane30RunReader(),
        _FakeReader('3.2'),
      ]);
      String line(String v) => two.select(LibreLaneVersion.tryParse(v)).$1.line;
      expect(line('3.1.4'), '3.0');
      expect(line('3.2.0'), '3.2');
      expect(line('3.9.0'), '3.2');
      expect(line('2.0.0'), '3.0');
    });
  });

  group('each fixture reads as its hand-written expectation', () {
    for (final MapEntry(key: version, value: names) in _cases.entries) {
      for (final name in names) {
        test('$version/$name', () async {
          final dir = _run(version, name);
          expect(Directory(dir).existsSync(), isTrue, reason: '$dir missing');
          final want = _expected(version, name);
          final reading = await LibreLaneReaders.standard().read(dir);
          final run = reading.run;

          expect(run.verdict.wireName, want['verdict']);
          expect(reading.version?.raw, want['librelane_version']);
          expect(run.ref.verified, isTrue);
          expect(run.ref.readerVersion, '3.0');
          expect(reading.unsupported, isNull);
          expect(run.toolVersions['librelane'], want['librelane_version']);
          expect(reading.pdk, want['pdk']);
          expect(reading.stdCellLibrary, want['std_cell_library']);

          expect(run.steps.last.dir, want['last_step']);
          expect(
            [
              for (final s in run.steps)
                if (s.status != FlowStepStatus.completed) s.dir,
            ],
            want['steps_without_state_out'],
          );
          final ids = want['step_ids']! as Map<String, Object?>;
          for (final MapEntry(:key, :value) in ids.entries) {
            expect(
              run.steps.singleWhere((s) => s.dir == key).id,
              value,
              reason: key,
            );
          }
          expect(reading.skippedSteps, want['gated_off_steps']);
          for (final text in want['error_log_contains']! as List<Object?>) {
            expect(
              reading.errorRecords.any((l) => l.contains(text! as String)),
              isTrue,
              reason: '$text',
            );
          }
          if (want['final_metrics'] == true) {
            expect(reading.metrics?.source, 'final/metrics.json');
            final metrics = want['metrics']! as Map<String, Object?>;
            for (final MapEntry(:key, :value) in metrics.entries) {
              expect(run.metrics[key], value, reason: key);
            }
            for (final key
                in (want['absent_metrics'] as List<Object?>?) ?? const []) {
              expect(run.metrics.containsKey(key), isFalse);
              expect(reading.checks!.absent, contains(key));
            }
            expect(reading.stoppedStep, isNull);
          } else {
            expect(reading.metrics, isNull);
            final stopped = (want['steps_without_state_out']! as List).last;
            expect(reading.stoppedStep, ids[stopped]);
          }
          // Every step that completed has its runtime.
          for (final s in run.steps) {
            if (s.status == FlowStepStatus.completed) {
              expect(s.runtime, isNotNull, reason: s.dir);
            }
          }
        });
      }
    }
  });

  group('LibreLane30RunReader against its own fixture directories', () {
    for (final version in ['3.0.15', '3.0.16', '3.0.17']) {
      test('$version sky130A_met', () async {
        final reading = await const LibreLane30RunReader().read(
          _run(version, 'sky130A_met'),
          version: LibreLaneVersion.tryParse(version),
        );
        expect(reading.verdict, FlowVerdict.met);
        expect(reading.verified, isTrue);
        expect(reading.run.steps, hasLength(76));
        expect(reading.checks!.findings.where((f) => f.violates), isEmpty);
      });
    }
  });

  group('verdict rules', () {
    test('an enforced check fails: setup at a checked corner', () async {
      final reading = await LibreLaneReaders.standard().read(
        _run('3.0.16', 'sky130A_timing'),
      );
      final setup = reading.checks!.findings.singleWhere(
        (f) => f.check.metric == 'timing__setup_vio__count',
      );
      expect(setup.enforced, isTrue);
      expect(setup.corners, contains('nom_tt_025C_1v80'));
      expect(setup.corners, contains('nom_ss_100C_1v60'));
    });

    test(
      'a check no LibreLane checker enforces still violates: antenna',
      () async {
        final reading = await LibreLaneReaders.standard().read(
          _run('3.0.16', 'sky130A_antenna'),
        );
        expect(reading.verdict, FlowVerdict.violated);
        final antenna = reading.checks!.findings
            .where((f) => f.check.category == LibreLaneCheckCategory.antenna)
            .toList();
        expect(antenna.map((f) => f.check.metric), [
          'route__antenna_violation__count',
          'antenna__violating__nets',
        ]);
        expect(antenna.every((f) => !f.enforced && f.violates), isTrue);
        // No step failed: LibreLane exits 0 on this run.
        expect(
          reading.run.steps.every((s) => s.status == FlowStepStatus.completed),
          isTrue,
        );
      },
    );

    test('a waived check is kept and leaves the verdict alone', () async {
      // gf180mcuD: max capacitance violations at every corner, which
      // MAX_CAP_VIOLATION_CORNERS ([""]) tells LibreLane not to check.
      final reading = await LibreLaneReaders.standard().read(
        _run('3.0.16', 'gf180mcuD_met'),
      );
      expect(reading.verdict, FlowVerdict.met);
      final cap = reading.checks!.findings.singleWhere(
        (f) => f.check.metric == 'design__max_cap_violation__count',
      );
      expect((cap.enforced, cap.violates), (false, false));
      // ERROR_ON_TR_DRC off in the DRC case: routing DRC is a note there.
      final drc = await LibreLaneReaders.standard().read(
        _run('3.0.16', 'sky130A_drc'),
      );
      final route = drc.checks!.findings.singleWhere(
        (f) => f.check.metric == 'route__drc_errors',
      );
      expect(route.enforced, isFalse);
      expect(
        drc.checks!.findings
            .where((f) => f.enforced)
            .map((f) => f.check.metric),
        containsAll(<String>[
          'magic__drc_error__count',
          'klayout__drc_error__count',
          'design__lvs_error__count',
        ]),
      );
    });

    test('a newer release reads best-effort and unverified', () async {
      final copy = _copy(_run('3.0.16', 'sky130A_met'));
      final resolved = File(p.join(copy.path, 'resolved.json'));
      final json =
          jsonDecode(resolved.readAsStringSync()) as Map<String, Object?>;
      (json['meta']! as Map<String, Object?>)['librelane_version'] = '3.0.18';
      resolved.writeAsStringSync(jsonEncode(json));
      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.verdict, FlowVerdict.met);
      expect(reading.verified, isFalse);
      expect(reading.unsupported, FlowReaderUnsupported.versionUnknown);
      expect(reading.version?.raw, '3.0.18');
    });

    test('a run without resolved.json is unverified, layout unknown', () async {
      final copy = _copy(_run('3.0.16', 'sky130A_met'));
      File(p.join(copy.path, 'resolved.json')).deleteSync();
      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.verified, isFalse);
      expect(reading.unsupported, FlowReaderUnsupported.layoutUnknown);
      expect(reading.verdict, FlowVerdict.met);
    });

    test('metrics.csv stands in for an absent metrics.json', () async {
      final copy = _copy(_run('3.0.16', 'sky130A_timing'));
      File(p.join(copy.path, 'final', 'metrics.json')).deleteSync();
      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.metrics!.source, 'final/metrics.csv');
      expect(reading.verdict, FlowVerdict.violated);
      expect(reading.run.metrics['timing__setup_vio__count'], 276);
    });

    test('a malformed metrics file is unrecognised, schema unknown', () async {
      final copy = _copy(_run('3.0.16', 'sky130A_met'));
      File(p.join(copy.path, 'final', 'metrics.json')).writeAsStringSync('[');
      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.verdict, FlowVerdict.unrecognised);
      expect(reading.unsupported, FlowReaderUnsupported.schemaUnknown);
      expect(reading.verified, isFalse);
    });

    test('a live run marks its newest unfinished step running', () async {
      final reading = await LibreLaneReaders.standard().read(
        _run('3.0.16', 'sky130A_stopped'),
        live: true,
      );
      expect(reading.run.steps.last.status, FlowStepStatus.running);
      expect(reading.verdict, FlowVerdict.stopped);
    });

    test('no directory is not run', () async {
      final reading = await LibreLaneReaders.standard().read(
        p.join(Directory.systemTemp.path, 'crux_flow_no_such_run_dir'),
      );
      expect(reading.verdict, FlowVerdict.notRun);
      expect(reading.verified, isFalse);
    });

    test('a step directory linking out of the run is not a step', () async {
      final copy = _copy(_run('3.0.16', 'sky130A_met'));
      final outside = Directory.systemTemp.createTempSync('crux_flow_out_');
      addTearDown(() => outside.deleteSync(recursive: true));
      File(p.join(outside.path, 'state_out.json')).writeAsStringSync('{}');
      Link(p.join(copy.path, '99-evil-step')).createSync(outside.path);
      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(
        reading.run.steps.map((s) => s.dir),
        isNot(contains('99-evil-step')),
      );
    });

    test('a resolved.json linking out of the run is refused', () async {
      final copy = _copy(_run('3.0.16', 'sky130A_met'));
      final outside = Directory.systemTemp.createTempSync('crux_flow_out_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final target = File(p.join(outside.path, 'resolved.json'))
        ..writeAsStringSync('{"meta": {"librelane_version": "3.0.16"}}');
      final resolved = File(p.join(copy.path, 'resolved.json'))..deleteSync();
      Link(resolved.path).createSync(target.path);
      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.verified, isFalse);
      expect(reading.unsupported, FlowReaderUnsupported.layoutUnknown);
    });
  });

  group('timing and artifacts', () {
    test(
      'the setup paths of the checked nominal corner, worst first',
      () async {
        final reading = await LibreLaneReaders.standard().read(
          _run('3.0.16', 'sky130A_timing'),
        );
        expect(reading.timingCorner, 'nom_tt_025C_1v80');
        final timing = reading.run.timing;
        // Counted independently: one "Startpoint:" line per path.
        final listing = File(
          p.join(
            _run('3.0.16', 'sky130A_timing'),
            reading.run.artifacts['sta_max'],
          ),
        ).readAsStringSync();
        final listed = RegExp(
          '^Startpoint: ',
          multiLine: true,
        ).allMatches(listing).length;
        expect(reading.timingPathCount, listed);
        expect(timing, hasLength(listed < 100 ? listed : 100));
        expect(timing.first.slackPs, lessThan(0));
        for (var i = 1; i < timing.length; i++) {
          expect(
            timing[i].slackPs,
            greaterThanOrEqualTo(timing[i - 1].slackPs!),
          );
          expect(timing[i].rank, i + 1);
        }
        expect(
          timing.every((t) => t.origin == TimingPathOrigin.openSta),
          isTrue,
        );
        final artifacts = reading.run.artifacts;
        expect(
          artifacts['synthesis_netlist'],
          '06-yosys-synthesis/path_adder.nl.v.json',
        );
        expect(artifacts['last_state'], endsWith('/state_out.json'));
        expect(artifacts['metrics'], 'final/metrics.json');
        expect(artifacts['sta_max'], contains('nom_tt_025C_1v80/max.rpt'));
      },
    );

    test('a corner whose listing was trimmed gives no paths', () async {
      final reading = await LibreLaneReaders.standard().read(
        _run('3.0.16', 'gf180mcuD_met'),
      );
      expect(reading.timingCorner, startsWith('nom_tt'));
      expect(reading.run.timing, isEmpty);
    });

    test('timingPaths: 0 reads none', () async {
      final reading = await LibreLaneReaders.standard().read(
        _run('3.0.16', 'sky130A_timing'),
        timingPaths: 0,
      );
      expect(reading.run.timing, isEmpty);
    });

    test('chooseLibreLaneTimingCorner', () {
      const corners = ['max_tt_1', 'nom_ff_1', 'nom_ss_1', 'nom_tt_1'];
      expect(chooseLibreLaneTimingCorner(corners, const {}), 'nom_ff_1');
      expect(
        chooseLibreLaneTimingCorner(corners, const {
          'TIMING_VIOLATION_CORNERS': ['*tt*'],
        }),
        'nom_tt_1',
      );
      expect(
        chooseLibreLaneTimingCorner(corners, const {
          'SETUP_VIOLATION_CORNERS': ['*ss*'],
          'TIMING_VIOLATION_CORNERS': ['*tt*'],
        }),
        'nom_ss_1',
      );
      expect(chooseLibreLaneTimingCorner(const ['x'], const {}), 'x');
      expect(chooseLibreLaneTimingCorner(const [], const {}), isNull);
    });
  });

  group('LibreLaneFlowLog', () {
    test('ids by directory, sub-steps left out, skips by name', () {
      final log = LibreLaneFlowLog.parse(
        "Running 'Yosys.Synthesis' at 'runs/a/06-yosys-synthesis'…\n"
        "Running 'OpenROAD.RepairAntennas' at '../x/runs/a/42-openroad-r'…\n"
        "Running 'OpenROAD.DiodeInsertion' at 'runs/a/42-openroad-r/1-d'…\n"
        "Skipping step 'Equivalence Check'…\n"
        "Running 'X' at 'not-a-step'\n",
      );
      expect(log.stepIds, {
        '06-yosys-synthesis': 'Yosys.Synthesis',
        '42-openroad-r': 'OpenROAD.RepairAntennas',
      });
      expect(log.skipped, ['Equivalence Check']);
    });
  });
}

class _FakeReader extends LibreLaneRunReader {
  _FakeReader(this.line);

  @override
  final String line;

  @override
  LibreLaneVersionRange get verified => LibreLaneVersionRange(
    LibreLaneVersion.tryParse('$line.0')!,
    LibreLaneVersion.tryParse('$line.0')!,
  );

  @override
  List<LibreLaneCheck> get checks => kLibreLane30Checks;

  @override
  MetricDefinitionTable get metricTable => librelaneMetricsV1;

  @override
  Future<LibreLaneReading> read(
    String runRoot, {
    String? tag,
    LibreLaneVersion? version,
    bool live = false,
    int timingPaths = 100,
  }) => throw UnimplementedError();
}
