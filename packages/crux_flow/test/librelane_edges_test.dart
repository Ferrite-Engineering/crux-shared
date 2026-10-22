// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _run(String version, String name) => p.normalize(
  Directory('test/fixtures/librelane/$version/$name/run').absolute.path,
);

Directory _temp() {
  final t = Directory.systemTemp.createTempSync('crux_flow_edge_');
  addTearDown(() => t.deleteSync(recursive: true));
  return Directory(t.resolveSymbolicLinksSync());
}

Directory _copy(String source) {
  final target = Directory(p.join(_temp().path, p.basename(source)))
    ..createSync();
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
  return target;
}

void main() {
  test('versions and ranges compare and print by their text', () {
    final a = LibreLaneVersion.tryParse('3.0.16')!;
    expect(a, const LibreLaneVersion(3, 0, 16));
    expect(a.hashCode, const LibreLaneVersion(3, 0, 16).hashCode);
    expect(a == LibreLaneVersion.tryParse('3.0.16.dev1'), isFalse);
    expect('$a', '3.0.16');
    expect('$kLibreLane30Verified', '3.0.15 to 3.0.16');
  });

  test('looksLikeRun', () {
    final root = _temp().path;
    final resolvedOnly = Directory(p.join(root, 'a'))..createSync();
    File(p.join(resolvedOnly.path, 'resolved.json')).writeAsStringSync('{}');
    final finalOnly = Directory(p.join(root, 'b', 'final'))
      ..createSync(recursive: true);
    final stepOnly = Directory(p.join(root, 'c', '01-yosys-x'))
      ..createSync(recursive: true);
    final neither = Directory(p.join(root, 'd', 'tmp'))
      ..createSync(recursive: true);
    expect(LibreLaneReaders.looksLikeRun(resolvedOnly.path), isTrue);
    expect(LibreLaneReaders.looksLikeRun(finalOnly.parent.path), isTrue);
    expect(LibreLaneReaders.looksLikeRun(stepOnly.parent.path), isTrue);
    expect(LibreLaneReaders.looksLikeRun(neither.parent.path), isFalse);
    expect(LibreLaneReaders.looksLikeRun(p.join(root, 'missing')), isFalse);
    final empty = Directory(p.join(root, 'e'))..createSync();
    expect(LibreLaneReaders.looksLikeRun(empty.path), isFalse);
  });

  test('an empty registry refuses to select', () {
    expect(
      () => const LibreLaneReaders(<LibreLaneRunReader>[]).select(null),
      throwsStateError,
    );
  });

  test('a malformed resolved.json is a schema problem, read on', () async {
    final copy = _copy(_run('3.0.16', 'sky130A_met'));
    File(p.join(copy.path, 'resolved.json')).writeAsStringSync('[1]');
    final reading = await LibreLaneReaders.standard().read(copy.path);
    expect(reading.unsupported, FlowReaderUnsupported.schemaUnknown);
    expect(reading.problem, startsWith('resolved.json:'));
    expect(reading.version, isNull);
    expect(reading.verified, isFalse);
  });

  test('over the byte cap: logs, metrics and the listing are problems, '
      'never a crash', () async {
    final reading = await LibreLaneReaders.standard(
      limits: const FlowInputLimits(maxBytes: 10000),
    ).read(_run('3.0.16', 'sky130A_timing'));
    expect(reading.problem, startsWith('run logs:'));
    expect(reading.verdict, FlowVerdict.unrecognised);
    expect(reading.unsupported, FlowReaderUnsupported.schemaUnknown);
    expect(reading.timingProblem, contains('over the cap'));
    expect(reading.run.timing, isEmpty);
  });

  test(
    'links out of the run are refused for logs, final/ and listings',
    () async {
      final copy = _copy(_run('3.0.16', 'sky130A_timing'));
      final outside = _temp();
      // flow.log
      final log = File(p.join(outside.path, 'flow.log'))..writeAsStringSync('');
      File(p.join(copy.path, 'flow.log')).deleteSync();
      Link(p.join(copy.path, 'flow.log')).createSync(log.path);
      // final/
      final fin = Directory(p.join(outside.path, 'final'))..createSync();
      File(p.join(fin.path, 'metrics.json')).writeAsStringSync('{}');
      Directory(p.join(copy.path, 'final')).deleteSync(recursive: true);
      Link(p.join(copy.path, 'final')).createSync(fin.path);
      // max.rpt
      final rpt = File(p.join(outside.path, 'max.rpt'))..writeAsStringSync('');
      final listing = File(
        p.join(copy.path, '55-openroad-stapostpnr/nom_tt_025C_1v80/max.rpt'),
      )..deleteSync();
      Link(listing.path).createSync(rpt.path);

      final reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.problem, startsWith('run logs:'));
      expect(reading.verdict, FlowVerdict.unrecognised);
      expect(reading.timingProblem, isNotNull);
      expect(reading.run.timing, isEmpty);
    },
  );

  test(
    'a corner without a setup listing, and an STA step without corners',
    () async {
      final copy = _copy(_run('3.0.16', 'sky130A_met'));
      final sta = p.join(copy.path, '55-openroad-stapostpnr');
      File(p.join(sta, 'nom_tt_025C_1v80', 'max.rpt')).deleteSync();
      var reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.timingProblem, 'the corner has no setup listing');
      for (final d in Directory(sta).listSync().whereType<Directory>()) {
        d.deleteSync(recursive: true);
      }
      reading = await LibreLaneReaders.standard().read(copy.path);
      expect(reading.timingProblem, 'the STA step lists no corner');
    },
  );

  test('step logs, step metrics and a step without runtime.txt', () async {
    final copy = _copy(_run('3.0.16', 'sky130A_met'));
    final step = p.join(copy.path, '06-yosys-synthesis');
    File(p.join(step, 'z.log')).writeAsStringSync('');
    File(p.join(step, 'yosys-synthesis.log')).writeAsStringSync('');
    File(p.join(step, 'or_metrics_out.json')).writeAsStringSync('{}');
    File(p.join(step, 'runtime.txt')).deleteSync();
    final steps = const LibreLaneStepReader().read(copy.path);
    final synth = steps.singleWhere((s) => s.dir == '06-yosys-synthesis');
    expect(synth.logPath, '06-yosys-synthesis/yosys-synthesis.log');
    expect(synth.metricsOut, '06-yosys-synthesis/or_metrics_out.json');
    expect(synth.runtime, isNull);
    expect(synth.tool, 'yosys');
    expect(
      const LibreLaneStepReader().read(p.join(copy.path, 'nope')),
      isEmpty,
    );
  });

  test('metrics.csv: header required, odd rows skipped, quotes undone', () {
    const reader = LibreLaneMetricsReader();
    expect(
      () => reader.parseCsv('Name,Value\n'),
      throwsA(isA<FlowReadException>()),
    );
    expect(
      () => const LibreLaneMetricsReader(
        limits: FlowInputLimits(maxBytes: 4),
      ).parseCsv('Metric,Value\n'),
      throwsA(isA<FlowReadException>()),
    );
    final doc = reader.parseCsv(
      'Metric,Value\n\nnocomma\n,x\na,"q ""1"""\nb,True\nc,None\nd,1.5E-9\n',
    );
    expect(doc.values, {'a': 'q "1"', 'b': true, 'c': null, 'd': 1.5e-9});
  });

  test('OpenSTA readFile: byte cap and UTF-8', () async {
    final dir = _temp();
    final big = File(p.join(dir.path, 'big.rpt'))..writeAsStringSync('x' * 100);
    expect(
      () => const OpenStaReportReader(
        limits: FlowInputLimits(maxBytes: 10),
      ).readFile(big.path),
      throwsA(isA<FlowReadException>()),
    );
    final bad = File(p.join(dir.path, 'bad.rpt'))
      ..writeAsBytesSync([0x53, 0xFF, 0xFE, 0x0A]);
    expect(
      () => const OpenStaReportReader().readFile(bad.path),
      throwsA(isA<FlowReadException>()),
    );
  });

  test('write_verilog numbering starts past existing _NNN_ names', () {
    final design = jsonEncode({
      'modules': {
        'top': {
          'attributes': {'top': '00000000000000000000000000000001'},
          'ports': <String, Object?>{},
          'cells': {
            r'$auto$c': {
              'type': 'dff',
              'port_directions': {'D': 'input', 'Q': 'output', 'CLK': 'input'},
              'connections': {
                'D': [2],
                'Q': [3],
                'CLK': [4],
              },
            },
            '_7_': {
              'type': 'buf',
              'connections': {
                'A': [3],
                'X': [5],
              },
            },
            r'\esc': {'type': 'buf', 'connections': <String, Object?>{}},
          },
          'netnames': {
            r'$auto$w': {
              'bits': [2],
              'hide_name': 1,
            },
            'r': {
              'bits': [3],
              'hide_name': 0,
            },
          },
        },
      },
    });
    final netlist = LibreLaneNetlist.parse(design);
    expect(netlist.sidecarName('_8_'), r'$auto$w');
    expect(netlist.sidecarName('_9_'), r'$auto$c');
    expect(netlist.sidecarName('_7_'), '_7_');
    expect(netlist.sidecarName(r'\\esc'), r'\esc');
    expect(netlist.sidecarName('nope'), isNull);
    expect(netlist.isStorage('_9_'), isTrue);
    expect(netlist.outputNets('_9_'), ['r']);
    expect(netlist.outputNets('nope'), isEmpty);
  });

  test('ports map by name, not as storage', () async {
    final run = _run('3.0.16', 'sky130A_timing');
    final reading = await LibreLaneReaders.standard().read(run);
    final netlist = await LibreLaneNetlist.read(
      p.join(run, reading.run.artifacts['synthesis_netlist']),
    );
    final registers = await RtlRegisterSet.read(
      'test/fixtures/elaboration/path_adder.json',
    );
    final toPort = reading.run.timing.firstWhere(
      (t) => !netlist.isStorage(t.endpoint),
    );
    final mapped = netlist.resolvePath(toPort, registers);
    expect(mapped.endpoint.fidelity, isNot(MappingFidelity.register));
    final fromPort = netlist.resolvePath(
      TimingPath(
        rank: 1,
        startpoint: 'not_a_cell',
        endpoint: toPort.endpoint,
        delayPs: 0,
        delayNs: 0,
        segments: const [],
        origin: TimingPathOrigin.openSta,
      ),
      registers,
    );
    expect(fromPort.startpoint.fidelity, MappingFidelity.unmapped);
  });

  test('every check has a SARIF rule and a message of its own', () {
    final findings = [
      for (final check in kLibreLane30Checks)
        LibreLaneFinding(check: check, value: 1, enforced: true),
    ];
    final reading = LibreLaneReading(
      run: const FlowRun(
        ref: FlowRunRef(
          kind: FlowKind.librelane,
          root: '/r',
          tag: 't',
          readerVersion: '3.0',
          verified: true,
        ),
        verdict: FlowVerdict.violated,
      ),
      checks: LibreLaneCheckOutcome(
        findings: findings,
        evaluated: const [],
        absent: const [],
      ),
    );
    final log = const FlowSarifWriter().librelane(reading);
    final results =
        ((log['runs']! as List).single as Map)['results']! as List<Object?>;
    expect(results, hasLength(kLibreLane30Checks.length));
    final rules = {
      for (final r
          in ((((log['runs']! as List).single as Map)['tool']!
                      as Map)['driver']!
                  as Map)['rules']!
              as List<Object?>)
        (r! as Map)['id'],
    };
    for (final r in results.cast<Map<String, Object?>>()) {
      expect(rules, contains(r['ruleId']));
      final text = (r['message']! as Map)['text']! as String;
      final metric = (r['properties']! as Map)['metric']! as String;
      expect(text, isNot(contains(metric)), reason: metric);
    }
    expect('${findings.first}', contains('timing__setup_vio__count'));
  });
}
