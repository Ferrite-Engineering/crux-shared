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

/// Registers and lines written from `path_adder.v`, not from any tool.
final Map<String, Object?> _mapping =
    jsonDecode(
          File(
            'test/fixtures/librelane/mapping.expected.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  late LibreLaneReading reading;
  late LibreLaneNetlist netlist;
  late RtlRegisterSet registers;

  setUpAll(() async {
    final run = _run('3.0.16', 'sky130A_timing');
    reading = await LibreLaneReaders.standard().read(run);
    netlist = await LibreLaneNetlist.read(
      p.join(run, reading.run.artifacts['synthesis_netlist']),
    );
    registers = await RtlRegisterSet.read(
      'test/fixtures/elaboration/path_adder.json',
    );
  });

  group('write_verilog names', () {
    test('every instance a timing path names is a sidecar cell or added '
        'by place and route', () {
      final pnrAdded = RegExp(
        r'^(clkbuf_|clkload|input\d|output\d|fanout\d|wire\d|hold\d|'
        'load_slew|max_cap|rebuffer|split|PHY_|TAP_|FILLER|ANTENNA)',
      );
      for (final path in reading.run.timing) {
        for (final s in path.segments) {
          for (final cell in [s.fromCell, s.toCell]) {
            final ports = path.startpoint == cell || path.endpoint == cell;
            if (netlist.sidecarName(cell) != null) continue;
            if (ports && !cell.startsWith('_')) continue;
            expect(pnrAdded.hasMatch(cell), isTrue, reason: cell);
          }
        }
      }
    });

    test('a register-to-register endpoint is a flip-flop with a named Q', () {
      final path = reading.run.timing.first;
      expect(netlist.isStorage(path.endpoint), isTrue);
      expect(netlist.outputNets(path.endpoint), isNotEmpty);
    });
  });

  group('G1 ">= 90": ASIC worst paths map to the nearest register', () {
    test('the worst register-to-register path maps start and end by name', () {
      final path = reading.run.timing.firstWhere(
        (t) => netlist.isStorage(t.startpoint) && netlist.isStorage(t.endpoint),
      );
      final mapped = netlist.resolvePath(path, registers);
      expect(mapped.endpoint.fidelity, MappingFidelity.register);
      expect(mapped.endpoint.register, _mapping['end_register']);
      expect(mapped.startpoint.fidelity, MappingFidelity.register);
      expect(
        _mapping['start_registers'],
        contains(mapped.startpoint.register),
      );
      expect(mapped.segments, hasLength(path.segments.length));
    });

    test('every register-to-register path of the listing maps both ends', () {
      final want = (_mapping['registers']! as List<Object?>).toSet();
      for (final path in reading.run.timing) {
        if (!netlist.isStorage(path.startpoint) ||
            !netlist.isStorage(path.endpoint)) {
          continue;
        }
        final mapped = netlist.resolvePath(path, registers);
        for (final end in [mapped.startpoint, mapped.endpoint]) {
          expect(end.fidelity, MappingFidelity.register, reason: '$path');
          expect(want, contains(end.register), reason: '$path');
        }
      }
    });

    test('registerNet strips bit and word selects', () {
      expect(
        LibreLaneNetlist.registerNet(['nope', 'sum_q[3]'], registers),
        'sum_q',
      );
      expect(LibreLaneNetlist.registerNet(['x[1][2]'], registers), 'x[1][2]');
      expect(LibreLaneNetlist.registerNet(const [], registers), isNull);
    });
  });

  group('FlowSarifWriter.librelane', () {
    Future<Map<String, Object?>> sarif(String name) async {
      final r = name == 'sky130A_timing'
          ? reading
          : await LibreLaneReaders.standard().read(_run('3.0.16', name));
      TimingPath? worst;
      TimingPathMapping? mapping;
      if (r.run.timing.isNotEmpty && name == 'sky130A_timing') {
        worst = r.run.timing.firstWhere(
          (t) =>
              netlist.isStorage(t.startpoint) && netlist.isStorage(t.endpoint),
        );
        mapping = netlist.resolvePath(worst, registers);
      }
      final log = const FlowSarifWriter(
        toolVersion: '1.2.0',
      ).librelane(r, worstSetupPath: worst, worstSetupMapping: mapping);
      // Round-trips as JSON.
      return jsonDecode(FlowSarifWriter.encode(log)) as Map<String, Object?>;
    }

    List<Map<String, Object?>> results(Map<String, Object?> log) => [
      for (final r in ((log['runs']! as List).single as Map)['results'] as List)
        r as Map<String, Object?>,
    ];

    test('a met run has no warnings', () async {
      final log = await sarif('sky130A_met');
      expect(log['version'], '2.1.0');
      expect(
        results(log).where((r) => r['level'] == 'warning'),
        isEmpty,
      );
    });

    test(
      'the timing case anchors its setup finding at the endpoint source',
      () async {
        final log = await sarif('sky130A_timing');
        final timing = results(log).singleWhere(
          (r) => r['ruleId'] == 'flow/timing-path',
        );
        expect(timing['level'], 'warning');
        final text = (timing['message']! as Map)['text']! as String;
        expect(text, contains(_mapping['end_register']));
        expect(text, isNot(contains('276')));
        final location =
            ((timing['locations']! as List).single as Map)['physicalLocation']
                as Map;
        expect((location['artifactLocation']! as Map)['uri'], 'path_adder.v');
        expect(timing['partialFingerprints'], isA<Map<String, Object?>>());
        final props = timing['properties']! as Map;
        expect(props['corners'], contains('nom_tt_025C_1v80'));
        expect(props['enforcedByLibreLane'], isTrue);
      },
    );

    test('the DRC case reports each check, without locations', () async {
      final all = results(await sarif('sky130A_drc'));
      final byMetric = {
        for (final r in all) (r['properties']! as Map)['metric']: r,
      };
      expect(byMetric['magic__drc_error__count']!['ruleId'], 'flow/drc');
      expect(byMetric['magic__drc_error__count']!['level'], 'warning');
      expect(byMetric['klayout__drc_error__count']!['ruleId'], 'flow/drc');
      expect(byMetric['design__lvs_error__count']!['ruleId'], 'flow/lvs');
      // ERROR_ON_TR_DRC is off in this case: a note, not a warning.
      expect(byMetric['route__drc_errors']!['level'], 'note');
      for (final r in all) {
        expect(r.containsKey('locations'), isFalse);
        final text = (r['message']! as Map)['text']! as String;
        expect(RegExp(r'\d').hasMatch(text), isFalse, reason: text);
      }
    });

    test('the antenna case reports antenna findings as warnings', () async {
      final all = results(await sarif('sky130A_antenna'));
      final antenna = all.where((r) => r['ruleId'] == 'flow/antenna').toList();
      expect(antenna, hasLength(2));
      expect(antenna.every((r) => r['level'] == 'warning'), isTrue);
    });

    test(
      'fingerprints are stable across a rerun of the same findings',
      () async {
        final a = results(await sarif('sky130A_drc'));
        final b = results(await sarif('sky130A_drc'));
        expect(
          [for (final r in a) r['partialFingerprints']],
          [for (final r in b) r['partialFingerprints']],
        );
      },
    );
  });
}
