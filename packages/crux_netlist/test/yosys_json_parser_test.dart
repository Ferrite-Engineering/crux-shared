// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:test/test.dart';

/// The parser's contract, which had no test coverage at all until 2026-08.
///
/// `crux_netlist` is consumed by NetCrux for every design a user opens, and
/// this class is the only thing standing between malformed `yosys -p
/// "write_json"` output and the rest of the app. Its stated promise is that
/// **no caller ever sees a raw `FormatException`, cast error or `TypeError`** —
/// everything arrives as a [YosysJsonParseException] with a message short
/// enough to render in a snackbar. That promise is what these tests pin; a
/// regression in it turns a bad netlist into an unhandled crash on the open
/// path.
const _parser = YosysJsonParser();

String _doc(Map<String, Object?> json) => jsonEncode(json);

Map<String, Object?> _module({
  Map<String, Object?>? attributes,
  Map<String, Object?>? ports,
  Map<String, Object?>? cells,
  Map<String, Object?>? netnames,
}) => <String, Object?>{
  'attributes': attributes ?? <String, Object?>{},
  'ports': ports ?? <String, Object?>{},
  'cells': cells ?? <String, Object?>{},
  'netnames': netnames ?? <String, Object?>{},
};

void main() {
  group('YosysJsonParser — the no-raw-errors contract', () {
    test('input that is not JSON at all', () {
      expect(
        () => _parser.parse('not json {'),
        throwsA(
          isA<YosysJsonParseException>()
              .having((e) => e.message, 'message', contains('not valid JSON'))
              .having((e) => e.cause, 'cause', isA<FormatException>()),
        ),
      );
    });

    test('valid JSON that is not an object', () {
      for (final raw in <String>['[]', '"a string"', '42', 'null', 'true']) {
        expect(
          () => _parser.parse(raw),
          throwsA(isA<YosysJsonParseException>()),
          reason: '$raw is not a JSON object',
        );
      }
    });

    test('a JSON object with no modules key', () {
      expect(
        () => _parser.parse(_doc(<String, Object?>{'creator': 'yosys'})),
        throwsA(
          isA<YosysJsonParseException>().having(
            (e) => e.message,
            'message',
            contains('modules'),
          ),
        ),
      );
    });

    test('modules present but the wrong type', () {
      for (final wrong in <Object?>[<Object?>[], 'x', 7]) {
        expect(
          () => _parser.parse(_doc(<String, Object?>{'modules': wrong})),
          throwsA(isA<YosysJsonParseException>()),
          reason: 'modules: $wrong',
        );
      }
    });

    test('a module whose body is the wrong type surfaces as a parse error', () {
      // This is the path the class doc calls out: a TypeError raised by a cast
      // inside fromJson, rewrapped rather than escaping as an Error.
      expect(
        () => _parser.parse(
          _doc(<String, Object?>{
            'modules': <String, Object?>{'top': 'not a map'},
          }),
        ),
        throwsA(isA<YosysJsonParseException>()),
      );
    });

    test('a malformed bit reference surfaces as a parse error', () {
      expect(
        () => _parser.parse(
          _doc(<String, Object?>{
            'modules': <String, Object?>{
              'top': _module(
                netnames: <String, Object?>{
                  'n': <String, Object?>{
                    'bits': <Object?>[
                      <String, Object?>{'not': 'a bit'},
                    ],
                  },
                },
              ),
            },
          }),
        ),
        throwsA(isA<YosysJsonParseException>()),
      );
    });

    test('no input shape escapes as a raw Error or FormatException', () {
      // The blanket assertion behind the individual cases above. If a future
      // change lets something through unwrapped, this fails even if nobody
      // thought to add a case for that shape.
      final hostile = <String>[
        '',
        '{',
        '{"modules": {"top": {"ports": 3}}}',
        '{"modules": {"top": {"cells": "x"}}}',
        '{"modules": {"top": {"netnames": []}}}',
        '{"modules": {"top": {"ports": {"a": {"direction": 5}}}}}',
        '{"modules": {"top": {"cells": {"c": {"connections": 1}}}}}',
      ];
      for (final raw in hostile) {
        try {
          _parser.parse(raw);
        } on YosysJsonParseException {
          continue; // the contract
        } on Object catch (e) {
          fail('parse($raw) escaped as ${e.runtimeType}: $e');
        }
      }
    });
  });

  group('YosysJsonParser — the happy path', () {
    test('an empty but well-formed document parses to an empty model', () {
      final model = _parser.parse(
        _doc(<String, Object?>{
          'creator': 'Yosys 0.40',
          'modules': <String, Object?>{},
        }),
      );
      expect(model.creator, 'Yosys 0.40');
      expect(model.modules, isEmpty);
      expect(model.topModule, isNull);
    });

    test('creator is optional and degrades to empty rather than throwing', () {
      final model = _parser.parse(
        _doc(<String, Object?>{'modules': <String, Object?>{}}),
      );
      expect(model.creator, isEmpty);
    });

    test('a module with ports, cells and nets round-trips through toJson', () {
      final raw = _doc(<String, Object?>{
        'creator': 'Yosys 0.40',
        'modules': <String, Object?>{
          'counter': _module(
            attributes: <String, Object?>{'top': 1},
            ports: <String, Object?>{
              'clk': <String, Object?>{
                'direction': 'input',
                'bits': <Object?>[2],
              },
              'q': <String, Object?>{
                'direction': 'output',
                'bits': <Object?>[3, 4],
              },
            },
            cells: <String, Object?>{
              'ff': <String, Object?>{
                'type': r'$dff',
                'connections': <String, Object?>{
                  'C': <Object?>[2],
                  'Q': <Object?>[3],
                },
              },
            },
            netnames: <String, Object?>{
              'n0': <String, Object?>{
                'bits': <Object?>[3],
              },
            },
          ),
        },
      });

      final model = _parser.parse(raw);
      expect(model.modules.keys, <String>['counter']);
      expect(model.topModule?.name, 'counter');

      // Re-parsing the serialized form must yield the same model — that is
      // what makes toJson usable for session persistence.
      final reparsed = _parser.parse(jsonEncode(model.toJson()));
      expect(reparsed.modules.keys, model.modules.keys);
      expect(reparsed.topModule?.name, 'counter');
    });

    test('topModule is null when no module claims it', () {
      final model = _parser.parse(
        _doc(<String, Object?>{
          'modules': <String, Object?>{'a': _module(), 'b': _module()},
        }),
      );
      expect(model.modules, hasLength(2));
      expect(model.topModule, isNull);
    });
  });
}
