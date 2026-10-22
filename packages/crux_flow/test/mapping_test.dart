// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:crux_flow/src/mapping/rtl_registers.dart';
import 'package:crux_netlist/crux_netlist.dart' show YosysJsonParser;
import 'package:test/test.dart';

const _elaboration = 'test/fixtures/elaboration';
const _nextpnr = 'test/fixtures/nextpnr';

/// The expectations written from `rtl/path_adder.v`, never from a tool.
final Map<String, Object?> _expected =
    jsonDecode(File('$_nextpnr/mapping.expected.json').readAsStringSync())
        as Map<String, Object?>;

RtlRegisterSet _registers(String name) => RtlRegisterSet.parse(
  File('$_elaboration/$name.json').readAsStringSync(),
);

/// A hand-written Yosys document: [modules] as given, the first marked top.
String _design(Map<String, Object?> modules) {
  final entries = modules.entries.toList();
  return jsonEncode({
    'creator': 'hand-written',
    'modules': {
      for (final (i, e) in entries.indexed)
        e.key: {
          ...(e.value! as Map<String, Object?>),
          if (i == 0) 'attributes': {'top': '1'},
        },
    },
  });
}

/// A module with one `$dff` per name in [registers], each storing a net of
/// that name declared at line `10 + i` and assigned by an `$add` on line
/// `20 + i`.
Map<String, Object?> _registerModule(
  List<String> registers, {
  Map<String, Object?> extraCells = const {},
}) {
  final cells = <String, Object?>{};
  final nets = <String, Object?>{};
  for (final (i, name) in registers.indexed) {
    final q = 100 + i * 10;
    final d = q + 1;
    cells['ff_$i'] = {
      'type': r'$dff',
      'attributes': {'src': 'h.v:5.3-30.6'},
      'port_directions': {'CLK': 'input', 'D': 'input', 'Q': 'output'},
      'connections': {
        'CLK': [2],
        'D': [d],
        'Q': [q],
      },
    };
    cells['add_$i'] = {
      'type': r'$add',
      'attributes': {'src': 'h.v:${20 + i}.10-${20 + i}.20'},
      'port_directions': {'A': 'input', 'B': 'input', 'Y': 'output'},
      'connections': {
        'A': [q],
        'B': ['1'],
        'Y': [d],
      },
    };
    nets[name] = {
      'hide_name': 0,
      'bits': [q],
      'attributes': {'src': 'h.v:${10 + i}.5-${10 + i}.9'},
    };
  }
  cells.addAll(extraCells);
  return {'cells': cells, 'netnames': nets};
}

void main() {
  group('RtlRegisterSet over the designed-path elaboration', () {
    final registers = _registers('path_adder');
    final declarations =
        (_expected['declaration_lines']! as Map<String, Object?>)
            .cast<String, int>();

    test('finds exactly the registers the source declares', () {
      expect(registers.registers.map((r) => r.name).toSet(), {
        ...(_expected['start_registers']! as List).cast<String>(),
        _expected['end_register']! as String,
      });
      expect(registers.sourceFiles, {'path_adder.v'});
    });

    test('each register is declared on its source line', () {
      for (final MapEntry(key: name, value: line) in declarations.entries) {
        final declared = registers[name]!.declaration;
        expect(declared, hasLength(1), reason: name);
        expect(declared.single.startLine, line, reason: name);
        expect(declared.single.file, 'path_adder.v');
      }
    });

    test('the deep path statement assigns the end register', () {
      final line = _expected['path_statement_line']! as int;
      final end = registers[_expected['end_register']! as String]!;
      expect(end.assignments.map((s) => s.startLine), contains(line));
      expect(
        registers
            .assignedAt(
              SrcSpan(file: 'path_adder.v', startLine: line, endLine: line),
            )
            .map((r) => r.name),
        [end.name],
      );
      // The shift registers are assigned by no cell of their own.
      expect(registers['src_a']!.assignments, isEmpty);
      // All three come from the one always block.
      for (final r in registers.registers) {
        expect(r.blocks.single.startLine, 13);
        expect(r.blocks.single.endLine, 17);
      }
    });

    test('a span recorded with a different directory still matches', () {
      expect(
        registers
            .declaredAt(
              const SrcSpan(
                file: '/home/ci/work/rtl/path_adder.v',
                startLine: 12,
                startCol: 14,
                endLine: 12,
                endCol: 19,
              ),
            )
            .map((r) => r.name),
        ['sum_q'],
      );
      expect(
        registers.declaredAt(
          const SrcSpan(file: 'other.v', startLine: 12),
        ),
        isEmpty,
      );
      expect(
        registers.sourceFileOf('<yosys-share>/ice40/arith_map.v'),
        isNull,
      );
    });
  });

  group('RtlRegisterSet over the multiplier elaboration', () {
    final registers = _registers('top');

    test('registers, outputs included, and their statements', () {
      expect(registers.registers.map((r) => r.name).toSet(), {
        'ra',
        'rb',
        'prod',
        'acc',
        'z',
      });
      expect(
        registers['prod']!.assignments.map((s) => s.startLine),
        contains(16),
      );
      expect(
        registers['acc']!.assignments.map((s) => s.startLine),
        contains(19),
      );
    });

    test('the name stem of a synthesized flip-flop', () {
      expect(registers.registerForCellName('ra_SB_DFF_Q_2_DFFLC')?.name, 'ra');
      expect(registers.registerForCellName('rb_TRELLIS_FF_Q_5')?.name, 'rb');
      expect(
        registers.registerForCellName('acc_SB_DFFSR_Q_12_D_SB_LUT4_O_LC')?.name,
        'acc',
      );
      expect(registers.registerForCellName('acc')?.name, 'acc');
      expect(
        registers.registerForCellName(r'$auto$ff.cc:337:slice$139'),
        isNull,
      );
      expect(registers.registerForCellName('rabbit_SB_DFF_Q'), isNull);
      expect(registers.registerForCellName(''), isNull);
    });
  });

  group('RtlRegisterSet on hand-written designs', () {
    test('the longest register name wins the stem', () {
      final set = RtlRegisterSet.parse(
        _design({
          't': _registerModule(['sum', 'sum_q']),
        }),
      );
      expect(set.registerForCellName('sum_q_SB_DFF_Q_3')?.name, 'sum_q');
      expect(set.registerForCellName('sum_SB_DFF_Q_3')?.name, 'sum');
    });

    test('registers below the top are named by instance path', () {
      final set = RtlRegisterSet.parse(
        _design({
          'top': _registerModule(
            ['state'],
            extraCells: {
              'u_div': {'type': 'div', 'connections': <String, Object?>{}},
            },
          ),
          'div': _registerModule(['cnt_q']),
        }),
      );
      expect(set.registers.map((r) => r.name).toSet(), {
        'state',
        'u_div.cnt_q',
      });
      expect(
        set.registerForCellName('u_div.cnt_q_SB_DFF_Q')?.name,
        'u_div.cnt_q',
      );
    });

    test('a module that instantiates itself is not re-entered', () {
      final set = RtlRegisterSet.parse(
        _design({
          'loop': _registerModule(
            ['r'],
            extraCells: {
              'again': {'type': 'loop', 'connections': <String, Object?>{}},
            },
          ),
        }),
      );
      expect(set.registers.map((r) => r.name), ['r']);
    });

    test('an instance tree past its bound is refused', () {
      final modules = <String, Object?>{};
      for (var i = 0; i < 6; i++) {
        modules['m$i'] = _registerModule(
          ['r'],
          extraCells: {
            for (var k = 0; k < 4; k++)
              'u$k': {'type': 'm${i + 1}', 'connections': <String, Object?>{}},
          },
        );
      }
      modules['m6'] = _registerModule(['r']);
      final text = _design(modules);
      expect(
        () => RtlRegisterSet.fromModel(
          const YosysJsonParser().parse(text),
          maxInstances: 100,
        ),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.tooLarge,
          ),
        ),
      );
      final shallow = RtlRegisterSet.fromModel(
        const YosysJsonParser().parse(text),
        maxDepth: 2,
      );
      expect(shallow.registers.map((r) => r.name).toSet(), {
        'r',
        for (var k = 0; k < 4; k++) 'u$k.r',
        for (var k = 0; k < 4; k++)
          for (var j = 0; j < 4; j++) 'u$k.u$j.r',
      });
    });

    test('a storage cell in a block that assigns one register names it', () {
      final set = RtlRegisterSet.parse(
        _design({
          't': _registerModule(['only']),
        }),
      );
      expect(set.length, 1);
      final m = RtlRegisterResolver(set).resolve(
        cell: r'$auto$slice$1',
        sources: ['h.v:5.3-30.6'],
        storage: true,
      );
      expect(m.fidelity, MappingFidelity.register);
      expect(m.register, 'only');
      expect(m.spans.first.startLine, 10);
    });

    test('registers and path mappings compare by value', () {
      final a = RtlRegisterSet.parse(
        _design({
          't': _registerModule(['r']),
        }),
      )['r']!;
      final b = RtlRegisterSet.parse(
        _design({
          't': _registerModule(['r']),
        }),
      )['r']!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const RtlRegister(name: 'r')));
      expect(a.toString(), 'RtlRegister(r)');
      const u = RtlMapping.unmapped;
      expect(
        const TimingPathMapping(startpoint: u, endpoint: u, segments: [u]),
        const TimingPathMapping(startpoint: u, endpoint: u, segments: [u]),
      );
      expect(
        const TimingPathMapping(
          startpoint: u,
          endpoint: u,
          segments: [u],
        ).hashCode,
        const TimingPathMapping(
          startpoint: u,
          endpoint: u,
          segments: [u],
        ).hashCode,
      );
    });

    test('both read their design from a file', () async {
      final set = await RtlRegisterSet.read('$_elaboration/path_adder.json');
      expect(set.length, 3);
      final index = await NetlistSrcIndex.read(
        'test/fixtures/synthesized/path_adder_ice40.json',
      );
      expect(index.moduleName, 'path_adder');
      final named = await NetlistSrcIndex.read(
        '$_elaboration/top.json',
        module: 'top',
      );
      expect(named.moduleName, 'top');
    });

    test('no top and several modules is refused; a named top is used', () {
      final text = jsonEncode({
        'modules': {
          'a': _registerModule(['x']),
          'b': _registerModule(['y']),
        },
      });
      expect(
        () => RtlRegisterSet.parse(text),
        throwsA(isA<FlowReadException>()),
      );
      expect(
        RtlRegisterSet.parse(text, top: 'b').registers.map((r) => r.name),
        ['y'],
      );
      expect(
        () => RtlRegisterSet.parse(text, top: 'c'),
        throwsA(isA<FlowReadException>()),
      );
    });
  });

  group('NetlistSrcIndex over a synthesized design', () {
    final index = NetlistSrcIndex.parse(
      File(
        'test/fixtures/synthesized/path_adder_ice40.json',
      ).readAsStringSync(),
    );

    test('indexes the top module', () {
      expect(index.moduleName, 'path_adder');
      expect(index.cellCount, greaterThan(70));
      expect(index.netCount, greaterThan(0));
      expect(index.cellNames, contains('sum_q_SB_DFF_Q'));
    });

    test('cell spans, declaration first, library spans kept', () {
      final spans = index.spansOfCell('sum_q_SB_DFF_Q');
      expect(spans.first, SrcSpan.tryParse('path_adder.v:13.3-17.6'));
      expect(spans.last.file, '<yosys-share>/ice40/ff_map.v');
      expect(index.spansOfCell('no such cell'), isEmpty);
      expect(index.spansOfNet('sum_q').single.startLine, 12);
    });

    test('flip-flops are storage, logic and carry cells are not', () {
      expect(index.typeOfCell('sum_q_SB_DFF_Q'), 'SB_DFF');
      expect(index.isStorage('sum_q_SB_DFF_Q'), isTrue);
      expect(index.isStorage('sum_q_SB_DFF_Q_2_D_SB_LUT4_O'), isFalse);
      expect(
        index.isStorage('sum_q_SB_DFF_Q_2_D_SB_LUT4_O_I3_SB_CARRY_CO'),
        isFalse,
      );
      expect(index.isStorage('absent'), isFalse);
      expect(index.containsCell('absent'), isFalse);
    });

    test(
      'with the index, a synthesized cell maps to its register and line',
      () {
        final resolver = RtlRegisterResolver(
          _registers('path_adder'),
          index: index,
        );
        final ff = resolver.resolve(cell: 'sum_q_SB_DFF_Q_7');
        expect(ff.fidelity, MappingFidelity.register);
        expect(ff.register, 'sum_q');
        expect(ff.spans.first.startLine, 12);
        final lut = resolver.resolve(cell: 'sum_q_SB_DFF_Q_2_D_SB_LUT4_O');
        expect(lut.fidelity, MappingFidelity.statement);
        expect(lut.register, 'sum_q');
        expect(lut.spans.first.startLine, 16);
      },
    );

    test('a design that is not a Yosys document is a FlowReadException', () {
      for (final text in ['[]', '{}', '{"modules": 3}', 'not json']) {
        expect(
          () => NetlistSrcIndex.parse(text),
          throwsA(isA<FlowReadException>()),
          reason: text,
        );
      }
      expect(
        () => NetlistSrcIndex.parse(
          '{"modules": {}}',
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
  });

  group('RtlRegisterResolver on the designed-path FPGA fixtures', () {
    final resolver = RtlRegisterResolver(_registers('path_adder'));
    final starts = (_expected['start_registers']! as List).cast<String>();
    final end = _expected['end_register']! as String;
    final line = _expected['path_statement_line']! as int;
    final declarations =
        (_expected['declaration_lines']! as Map<String, Object?>)
            .cast<String, int>();
    final cases = (_expected['cases']! as Map<String, Object?>)
        .cast<String, Map<String, Object?>>();

    test('every case in the expectations has a report', () {
      expect(cases, isNotEmpty);
      for (final name in cases.keys) {
        expect(
          File('$_nextpnr/$name/report.json').existsSync(),
          isTrue,
          reason: '$name is missing',
        );
      }
    });

    for (final MapEntry(key: name, value: facts) in cases.entries) {
      test(name, () {
        final report = const NextpnrReportReader().parse(
          File('$_nextpnr/$name/report.json').readAsStringSync(),
        );
        final worst = report.criticalPaths.firstWhere(
          (p) => p.clockFrom != null && p.clockTo != null,
        );
        final mapping = resolver.resolvePath(worst);

        // The start is one of the two shift registers, by name or by the
        // net the flip-flop drives.
        expect(mapping.startpoint.fidelity, MappingFidelity.register);
        expect(starts, contains(mapping.startpoint.register));
        expect(
          mapping.startpoint.spans.first.startLine,
          declarations[mapping.startpoint.register],
        );

        // The end is the sum register: named when the cell names carry it,
        // otherwise found through the statement that assigns it.
        expect(mapping.endpoint.register, end);
        if (facts['cell_names_carry_register']! as bool) {
          expect(mapping.endpoint.fidelity, MappingFidelity.register);
          expect(mapping.endpoint.spans.first.startLine, declarations[end]);
        } else {
          expect(mapping.endpoint.fidelity, MappingFidelity.statement);
          expect(mapping.endpoint.spans.first.startLine, line);
        }

        // Somewhere along the path a segment lands on the adder's line.
        expect(
          mapping.segments.any(
            (m) =>
                m.fidelity == MappingFidelity.statement &&
                m.spans.first.startLine == line &&
                m.register == end,
          ),
          isTrue,
        );
        expect(mapping.segments, hasLength(worst.segments.length));
        // Nothing maps to a line the design does not have.
        for (final m in [
          mapping.startpoint,
          mapping.endpoint,
          ...mapping.segments,
        ]) {
          for (final s in m.spans) {
            expect(s.file, endsWith('path_adder.v'));
            expect(s.startLine, inInclusiveRange(1, 19));
          }
        }
      });
    }
  });

  group('RtlRegisterResolver levels', () {
    final resolver = RtlRegisterResolver(_registers('path_adder'));

    test('only tool-library spans, or none, are unmapped', () {
      expect(
        resolver.resolve(
          cell: r'$nextpnr_ICESTORM_LC_0',
          sources: ['<yosys-share>/ice40/cells_map.v:6.21-6.22'],
        ),
        RtlMapping.unmapped,
      );
      expect(resolver.resolve(cell: 'x'), RtlMapping.unmapped);
    });

    test('a block span alone is span fidelity, unless storage pins it', () {
      final block = resolver.resolve(sources: ['path_adder.v:13.3-17.6']);
      expect(block.fidelity, MappingFidelity.span);
      expect(block.register, isNull);
      // Three registers share the block, so storage alone names none.
      expect(
        resolver
            .resolve(
              cell: 'f',
              sources: ['path_adder.v:13.3-17.6'],
              storage: true,
            )
            .fidelity,
        MappingFidelity.span,
      );
    });

    test('a single-line span that assigns nothing is a statement alone', () {
      final m = resolver.resolve(sources: ['path_adder.v:18.14-18.20']);
      expect(m.fidelity, MappingFidelity.statement);
      expect(m.register, isNull);
    });

    test('a declaration span names its register', () {
      final m = resolver.resolve(
        net: 'x',
        sources: ['path_adder.v:11.14-11.19'],
      );
      expect(m.fidelity, MappingFidelity.register);
      expect(m.register, 'src_b');
    });

    test('a register output net names its register', () {
      expect(resolver.resolve(net: 'src_a[7]').register, 'src_a');
      expect(resolver.resolve(net: 'src_a').register, 'src_a');
      expect(resolver.resolve(net: 'src_ab[1]'), RtlMapping.unmapped);
    });

    test('storage is needed for the name stem', () {
      expect(
        resolver.resolve(cell: 'sum_q_SB_DFF_Q_3').fidelity,
        MappingFidelity.unmapped,
      );
      expect(
        resolver.resolve(cell: 'sum_q_SB_DFF_Q_3', storage: true).register,
        'sum_q',
      );
    });

    test('nearestMapped looks both ways, earlier first', () {
      const u = RtlMapping.unmapped;
      const m = RtlMapping(fidelity: MappingFidelity.span);
      const mapping = TimingPathMapping(
        startpoint: u,
        endpoint: u,
        segments: [u, m, u, u, m],
      );
      expect(mapping.nearestMapped(0), 1);
      expect(mapping.nearestMapped(2), 1);
      expect(mapping.nearestMapped(3), 4);
      expect(
        const TimingPathMapping(
          startpoint: u,
          endpoint: u,
          segments: [u],
        ).nearestMapped(0),
        isNull,
      );
    });
  });

  group('isToolLibraryPath', () {
    test('Yosys share and techlibs paths, in both styles', () {
      expect(isToolLibraryPath('<yosys-share>/ice40/cells_map.v'), isTrue);
      expect(isToolLibraryPath('/opt/oss/share/yosys/ice40/ff_map.v'), isTrue);
      expect(
        isToolLibraryPath(r'C:\oss\share\yosys\gowin\arith_map.v'),
        isTrue,
      );
      expect(
        isToolLibraryPath('/src/yosys/techlibs/ice40/cells_map.v'),
        isTrue,
      );
      expect(isToolLibraryPath('rtl/share/top.v'), isFalse);
      expect(isToolLibraryPath('path_adder.v'), isFalse);
    });
  });

  test('sameSourceRange ignores a column only one side records', () {
    expect(
      sameSourceRange(
        const SrcSpan(file: 'a', startLine: 3, startCol: 2, endLine: 3),
        const SrcSpan(file: 'b', startLine: 3),
      ),
      isTrue,
    );
    expect(
      sameSourceRange(
        const SrcSpan(file: 'a', startLine: 3, startCol: 2),
        const SrcSpan(file: 'a', startLine: 3, startCol: 4),
      ),
      isFalse,
    );
    expect(
      sameSourceRange(
        const SrcSpan(file: 'a', startLine: 3, endLine: 4),
        const SrcSpan(file: 'a', startLine: 3),
      ),
      isFalse,
    );
  });
}
