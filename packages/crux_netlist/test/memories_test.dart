// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_netlist/crux_netlist.dart';
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

    test('a structured attribute value is refused, naming the field', () {
      // A list or an object is never stringified: nested deeply enough, that
      // is quadratic in the depth and can spin for minutes.
      expect(
        () => NetlistModel.fromJson(
          _doc({
            'memories': {
              'm': {
                'attributes': {
                  'src': [
                    [1],
                  ],
                },
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
              contains('expected a string or a number'),
            ),
          ),
        ),
      );
    });

    test('scalar attribute values keep their JSON spelling', () {
      final model = NetlistModel.fromJson(
        _doc({
          'memories': {
            'm': {
              'attributes': {'a': 'x', 'b': 7, 'c': true, 'd': null},
            },
          },
        }),
      );
      expect(model.modules['top']!.memories['m']!.attributes, {
        'a': 'x',
        'b': '7',
        'c': 'true',
        'd': '',
      });
    });

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
