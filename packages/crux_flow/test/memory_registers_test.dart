// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

const _elaboration = 'test/fixtures/elaboration';

// The expectations are read off `regfile.v`, never off a tool or the
// resolver: the register file `cpuregs` is declared on line 15, the plain
// register `acc` on line 16, and the write `cpuregs[waddr] <= wdata + 8'd1`
// is line 18.
const _file = 'regfile.v';
const _memoryLine = 15;
const _accLine = 16;
const _writeLine = 18;

RtlRegisterSet _set(String name) =>
    RtlRegisterSet.parse(File('$_elaboration/$name.json').readAsStringSync());

bool _hasLine(Iterable<SrcSpan> spans, int line) =>
    spans.any((s) => s.startLine == line && s.file.endsWith(_file));

void main() {
  // The same RTL elaborated two ways: `hierarchy; proc` leaves the memory in
  // the `memories` section (what the suite's Yosys runner writes); after the
  // `memory` passes it is a `$mem_v2` cell.
  for (final form in const ['regfile', 'regfile_mem']) {
    group('a register file in the $form elaboration', () {
      late RtlRegisterSet set;
      setUp(() => set = _set(form));

      test('is one register, whatever its words', () {
        final names = set.registers.map((r) => r.name).toList();
        expect(names.where((n) => n.startsWith('cpuregs')), ['cpuregs']);
      });

      test('is declared at its own line', () {
        final memory = set['cpuregs']!;
        expect(memory.declaration, hasLength(1));
        expect(memory.declaration.single.startLine, _memoryLine);
        expect(memory.declaration.single.file, endsWith(_file));
      });

      test('is assigned by its write statement', () {
        final memory = set['cpuregs']!;
        if (form == 'regfile') {
          // `proc` keeps the write port's own statement; the `memory`
          // passes fold the ports into the memory's declaration.
          expect(_hasLine(memory.blocks, _writeLine), isTrue);
        }
        expect(_hasLine(memory.assignments, _writeLine), isTrue);
        expect(set.assignedAt(memory.assignments.first), contains(memory));
      });

      test('is found by the span that declares it', () {
        final span = set['cpuregs']!.declaration.single;
        expect(set.declaredAt(span).map((r) => r.name), ['cpuregs']);
        expect(set.sourceFileOf(span.file), isNotNull);
      });

      test('a word or bit of it maps to the register at register fidelity', () {
        final resolver = RtlRegisterResolver(set);
        for (final label in const ['cpuregs[2][5]', 'cpuregs[0]', 'cpuregs']) {
          final net = LibreLaneNetlist.registerNet([label], set);
          expect(net, 'cpuregs', reason: label);
          final mapping = resolver.resolve(net: net);
          expect(mapping.fidelity, MappingFidelity.register, reason: label);
          expect(mapping.register, 'cpuregs', reason: label);
          expect(mapping.spans.first.startLine, _memoryLine, reason: label);
        }
      });

      test('a flip-flop named after a word of it maps by cell name', () {
        final mapping = RtlRegisterResolver(
          set,
        ).resolve(cell: r'cpuregs[21][19]$_DFFE_PP_', storage: true);
        expect(mapping.fidelity, MappingFidelity.register);
        expect(mapping.register, 'cpuregs');
      });
    });
  }

  test('a plain register is still collected beside the memory', () {
    final set = _set('regfile');
    expect(set['acc']!.declaration.single.startLine, _accLine);
    expect(set.registers.map((r) => r.name), contains('cpuregs'));
  });

  group('memories of a hand-built design', () {
    Map<String, Object?> memoryModule({
      String memory = 'ram',
      bool hidden = false,
    }) => {
      'memories': {
        memory: {
          'hide_name': hidden ? 1 : 0,
          'attributes': {'src': 'h.v:7.3-7.12'},
          'width': 8,
          'start_offset': 0,
          'size': 4,
        },
      },
      'cells': {
        'wr': {
          'type': r'$memwr',
          'parameters': {'MEMID': '\\$memory'},
          'attributes': {'src': 'h.v:9.5-9.20'},
          'connections': {
            'DATA': <Object>[],
            'ADDR': <Object>[],
            'EN': <Object>[],
            'CLK': <Object>[],
          },
        },
      },
    };

    test('is collected under the instance path of a submodule', () {
      final text = jsonEncode({
        'modules': {
          'top': {
            'attributes': {'top': '1'},
            'cells': {
              'u': {'type': 'child', 'connections': <String, Object?>{}},
            },
          },
          'child': memoryModule(),
        },
      });
      final set = RtlRegisterSet.parse(text);
      expect(set.registers.map((r) => r.name), ['u.ram']);
      expect(set['u.ram']!.declaration.single.startLine, 7);
      expect(set['u.ram']!.blocks.single.startLine, 9);
    });

    test('an auto-named memory is not a register', () {
      final text = jsonEncode({
        'modules': {
          'top': {
            ...memoryModule(memory: r'$auto$mem', hidden: true),
            'attributes': {'top': '1'},
          },
        },
      });
      expect(RtlRegisterSet.parse(text).length, 0);
    });

    test('a design with no memories section reads as before', () {
      final text = jsonEncode({
        'modules': {
          'top': {
            'attributes': {'top': '1'},
          },
        },
      });
      expect(RtlRegisterSet.parse(text).length, 0);
    });
  });
}
