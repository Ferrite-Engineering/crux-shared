// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:crux_netlist/src/json_shape.dart' show maxJsonValueNesting;
import 'package:test/test.dart';

Map<String, Object?> _doc(Map<String, Object?> module) => {
  'modules': {'top': module},
};

void main() {
  group('Module.memories', () {
    final memories = {
      'cpuregs': {
        'hide_name': 0,
        'attributes': {'src': 'rf.v:15.13-15.20'},
        'width': 32,
        'start_offset': 0,
        'size': 31,
      },
    };

    test('reads the memories section as Yosys writes it', () {
      final model = NetlistModel.fromJson(_doc({'memories': memories}));
      final read = model.modules['top']!.memories['cpuregs']!;
      expect(read.name, 'cpuregs');
      expect(read.width, 32);
      expect(read.size, 31);
      expect(read.startOffset, 0);
      expect(read.hideName, isFalse);
      expect(read.attributes['src'], 'rf.v:15.13-15.20');
    });

    test('a module without the section has none', () {
      final model = NetlistModel.fromJson(_doc({}));
      expect(model.modules['top']!.memories, isEmpty);
      expect(model.modules['top']!.toJson().containsKey('memories'), isFalse);
    });

    test('round-trips through JSON', () {
      final model = NetlistModel.fromJson(_doc({'memories': memories}));
      final again = NetlistModel.fromJson(
        jsonDecode(jsonEncode(model.toJson())) as Map<String, Object?>,
      );
      expect(again.modules['top'], model.modules['top']);
      expect(again.modules['top']!.hashCode, model.modules['top']!.hashCode);
    });

    test('a memory of the wrong JSON type is a FormatException', () {
      expect(
        () => NetlistModel.fromJson(
          _doc({
            'memories': {'m': 3},
          }),
        ),
        throwsFormatException,
      );
    });

    test('an attribute nested past the cap is refused, naming the field', () {
      // Printing a collection is quadratic in its depth, so a value nested
      // deeply enough could spin for minutes. Past the cap it is refused
      // before anything prints it.
      Object? nested = 0;
      for (var i = 0; i <= maxJsonValueNesting; i++) {
        nested = <Object?>[nested];
      }
      expect(
        () => NetlistModel.fromJson(
          _doc({
            'memories': {
              'm': {
                'attributes': {'src': nested},
              },
            },
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('attributes.src'),
              contains('nested more than $maxJsonValueNesting levels deep'),
            ),
          ),
        ),
      );
    });

    test(
      'attribute values keep their spelling, structured ones as printed',
      () {
        final model = NetlistModel.fromJson(
          _doc({
            'memories': {
              'm': {
                'attributes': {
                  'a': 'x',
                  'b': 7,
                  'c': true,
                  'd': null,
                  'e': [1, 'x'],
                },
              },
            },
          }),
        );
        expect(model.modules['top']!.memories['m']!.attributes, {
          'a': 'x',
          'b': '7',
          'c': 'true',
          'd': '',
          'e': '[1, x]',
        });
      },
    );

    test('copyWith replaces memories', () {
      final module = NetlistModel.fromJson(_doc({})).modules['top']!;
      final copy = module.copyWith(
        memories: {'m': const Memory(name: 'm', width: 8, size: 4)},
      );
      expect(copy.memories, hasLength(1));
      expect(copy, isNot(module));
    });
  });
}
