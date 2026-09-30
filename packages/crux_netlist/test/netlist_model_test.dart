// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:test/test.dart';

/// The model layer, where a hostile `write_json` document lands.
///
/// Two things are pinned here.
///
/// **Hostile input is rejected or tolerated, never a crash.** Every document
/// below either parses or fails with a [YosysJsonParseException]. The model's
/// `fromJson` factories cast freely, and a failed cast is a `TypeError`; a
/// value nested deeply enough overflows the stack when stringified, which is a
/// `StackOverflowError`. Both are `Error`s, which walk straight through an
/// `on Exception` handler — so the parser is the boundary that must turn every
/// one of them into an `Exception`, and every case below checks the type of
/// what came out, not only that something did.
///
/// **Equality means the same netlist.** A model is compared to decide whether
/// a re-elaboration changed anything, and serialized with `toJson` to be
/// restored later. So a model must equal its own round trip, and must not
/// equal a model one bit, one direction or one attribute away from it.
void main() {
  group('hostile documents', () {
    // A document the parser must refuse, as a YosysJsonParseException.
    final rejected = <String, String>{
      'a module body that is null': '{"modules":{"top":null}}',
      'a module body that is a list': '{"modules":{"top":[]}}',
      'module attributes that are a list':
          '{"modules":{"top":{"attributes":[1,2]}}}',
      'a cell body that is null': _cells('{"c":null}'),
      'a cell with no type': _cells('{"c":{}}'),
      'a cell type that is a number': _cells('{"c":{"type":7}}'),
      'a cell hide_name that is a boolean': _cells(
        '{"c":{"type":"x","hide_name":true}}',
      ),
      'a cell hide_name that is fractional': _cells(
        '{"c":{"type":"x","hide_name":1.5}}',
      ),
      'a port direction that is a number': _cells(
        '{"c":{"type":"x","port_directions":{"A":1}}}',
      ),
      'a port direction that is null': _cells(
        '{"c":{"type":"x","port_directions":{"A":null}}}',
      ),
      'connections that are a string': _cells(
        '{"c":{"type":"x","connections":"A=1"}}',
      ),
      'a connection that is null': _cells(
        '{"c":{"type":"x","connections":{"A":null}}}',
      ),
      'a connection that is a string': _cells(
        '{"c":{"type":"x","connections":{"A":"0101"}}}',
      ),
      'a connection bit that is null': _bits('[null]'),
      'a connection bit that is a boolean': _bits('[true]'),
      'a connection bit that is fractional': _bits('[2.5]'),
      'a connection bit that is an object': _bits('[{"net":2}]'),
      'a connection bit that is an unknown letter': _bits('["q"]'),
      'a connection bit too large for an int': _bits('[99999999999999999999]'),
      'a connection bit of 1e400': _bits('[1e400]'),
      'a port with no direction': _ports('{"clk":{"bits":[2]}}'),
      'a port direction that is an object': _ports(
        '{"clk":{"direction":{},"bits":[2]}}',
      ),
      'port bits that are a string': _ports(
        '{"clk":{"direction":"input","bits":"2"}}',
      ),
      'a port body that is null': _ports('{"clk":null}'),
      'a net body that is null': _nets('{"n":null}'),
      'net bits that are an object': _nets('{"n":{"bits":{"0":2}}}'),
      'a net hide_name that is a string': _nets(
        '{"n":{"bits":[2],"hide_name":"1"}}',
      ),
      'net attributes that are a list': _nets(
        '{"n":{"bits":[2],"attributes":["src"]}}',
      ),
      'an attribute nested a hundred thousand deep':
          '{"modules":{"top":{"attributes":{"src":${_deep(100000)}}}}}',
      'a cell parameter nested a hundred thousand deep': _cells(
        '{"c":{"type":"x","parameters":{"W":${_deep(100000)}}}}',
      ),
      'a creator nested a hundred thousand deep':
          '{"creator":${_deep(100000)},"modules":{}}',
    };

    for (final entry in rejected.entries) {
      test('refused: ${entry.key}', () {
        expect(_outcome(entry.value), _Outcome.rejected);
      });
    }

    test('tolerated: shapes Yosys may vary, or that name nothing', () {
      // Each parses. What it parses to is checked where it matters.
      final creatorNumber = _parseOk('{"creator":42,"modules":{}}');
      expect(creatorNumber.creator, '42');

      final loose = _parseOk(
        _cells(
          '{"c":{"type":"x","parameters":[1],"attributes":7,'
          '"port_directions":{"A":"sideways"},'
          '"connections":{"A":[-1,"42","X","Z"]}}}',
        ),
      );
      final cell = loose.modules['top']!.cells['c']!;
      expect(cell.parameters, isEmpty, reason: 'a list is not parameters');
      expect(cell.attributes, isEmpty);
      expect(
        cell.portDirections['A'],
        PortDirection.inout,
        reason: 'an unknown direction degrades, it does not fail the file',
      );
      expect(cell.connections['A'], <BitRef>[
        const NetBit(-1),
        const NetBit(42),
        const ConstantBit(ConstantBitValue.x),
        const ConstantBit(ConstantBitValue.z),
      ]);

      final nulls = _parseOk(
        '{"modules":{"top":{"attributes":null,"ports":null,'
        '"cells":null,"netnames":null}}}',
      );
      expect(nulls.modules['top']!.cells, isEmpty);

      final emptyNames = _parseOk(
        '{"modules":{"":{"cells":{"":{"type":""}}}}}',
      );
      expect(emptyNames.modules['']!.cells[''], isNotNull);

      final deepElsewhere = _parseOk(
        '{"modules":{},"unrelated":${_deep(100000)}}',
      );
      expect(
        deepElsewhere.modules,
        isEmpty,
        reason: 'a key the model never reads is never stringified',
      );
    });

    test('tolerated: a net of two hundred thousand bits', () {
      final bits = List<int>.generate(200000, (i) => i + 2);
      final model = _parseOk(
        _nets(
          jsonEncode({
            'bus': {'bits': bits},
          }),
        ),
      );

      expect(model.modules['top']!.nets['bus']!.width, 200000);
    });

    test('tolerated: a cell with fifty thousand connections', () {
      final connections = <String, Object?>{
        for (var i = 0; i < 50000; i++) 'P$i': <int>[i + 2],
      };
      final model = _parseOk(
        _cells(
          jsonEncode({
            'wide': {'type': 'x', 'connections': connections},
          }),
        ),
      );

      expect(
        model.modules['top']!.cells['wide']!.connections,
        hasLength(50000),
      );
    });

    test('the exception says what went wrong, and keeps the cause', () {
      const bare = YosysJsonParseException('bad');
      expect(bare.toString(), 'YosysJsonParseException: bad');

      try {
        const YosysJsonParser().parse(_bits('[null]'));
        fail('a null bit parsed');
      } on YosysJsonParseException catch (e) {
        expect(e.cause, isNotNull);
        expect(e.toString(), contains('cause:'));
      }
    });
  });

  group('equality means the same netlist', () {
    final original = _richDocument();
    final model = const YosysJsonParser().parse(jsonEncode(original));

    test('a model equals its own round trip', () {
      final again = const YosysJsonParser().parse(jsonEncode(model.toJson()));

      expect(again, model);
      expect(again.hashCode, model.hashCode);
      for (final name in model.modules.keys) {
        final a = model.modules[name]!;
        final b = again.modules[name]!;
        expect(b, a);
        expect(b.hashCode, a.hashCode);
        for (final cell in a.cells.keys) {
          expect(b.cells[cell], a.cells[cell]);
          expect(b.cells[cell].hashCode, a.cells[cell].hashCode);
        }
        for (final net in a.nets.keys) {
          expect(b.nets[net], a.nets[net]);
          expect(b.nets[net].hashCode, a.nets[net].hashCode);
        }
        for (final port in a.ports.keys) {
          expect(b.ports[port], a.ports[port]);
          expect(b.ports[port].hashCode, a.ports[port].hashCode);
        }
      }
    });

    // Each edit is the smallest change of its kind. Every one must make the
    // model unequal to the original, or a consumer comparing the two would
    // miss a real change to the design.
    final edits = <String, void Function(Map<String, Object?> top)>{
      'the creator': (doc) => doc['creator'] = 'Yosys 0.99',
      'a module name': (doc) {
        final modules = doc['modules']! as Map<String, Object?>;
        modules['counter2'] = modules.remove('counter');
      },
      'a module attribute': (doc) => _top(doc)['attributes'] = {
        'top': '00000000000000000000000000000001',
        'src': 'other.v:1',
      },
      'a port direction': (doc) => _port(doc, 'q')['direction'] = 'inout',
      'a port bit': (doc) => _port(doc, 'q')['bits'] = [3, 5],
      'a port width': (doc) => _port(doc, 'q')['bits'] = [3],
      'a port removed': (doc) =>
          (_top(doc)['ports']! as Map<String, Object?>).remove('clk'),
      'a cell type': (doc) => _cell(doc, 'ff')['type'] = r'$adff',
      'a cell name marker': (doc) => _cell(doc, 'ff')['hide_name'] = 1,
      'a cell parameter': (doc) =>
          _cell(doc, 'ff')['parameters'] = {'WIDTH': '00000011'},
      'a cell attribute': (doc) =>
          _cell(doc, 'ff')['attributes'] = {'src': 'counter.v:99'},
      'a cell port direction': (doc) =>
          (_cell(doc, 'ff')['port_directions']! as Map)['Q'] = 'input',
      'a connection bit': (doc) =>
          (_cell(doc, 'ff')['connections']! as Map)['D'] = ['x', 4],
      'a connection width': (doc) =>
          (_cell(doc, 'ff')['connections']! as Map)['D'] = [5],
      'a connection renamed': (doc) {
        final connections = _cell(doc, 'ff')['connections']! as Map;
        connections['DD'] = connections.remove('D');
      },
      'a cell removed': (doc) =>
          (_top(doc)['cells']! as Map<String, Object?>).remove('inv'),
      'a net bit': (doc) => _net(doc, 'count')['bits'] = [3, 'z'],
      'a net name marker': (doc) => _net(doc, 'count')['hide_name'] = 1,
      'a net attribute value': (doc) =>
          _net(doc, 'count')['attributes'] = {'src': 'counter.v:2'},
      'a net attribute added': (doc) => _net(doc, 'count')['attributes'] = {
        'src': 'counter.v:3',
        'keep': '1',
      },
    };

    for (final edit in edits.entries) {
      test('a change to ${edit.key} is a different netlist', () {
        final doc = jsonDecode(jsonEncode(original)) as Map<String, Object?>;
        edit.value(doc);
        final changed = const YosysJsonParser().parse(jsonEncode(doc));

        expect(changed, isNot(model));
        expect(model, isNot(changed));
      });
    }

    test('copyWith with nothing changes nothing', () {
      final top = model.modules['counter']!;
      final cell = top.cells['ff']!;
      final net = top.nets['count']!;
      final port = top.ports['q']!;

      expect(model.copyWith(), model);
      expect(top.copyWith(), top);
      expect(cell.copyWith(), cell);
      expect(net.copyWith(), net);
      expect(port.copyWith(), port);
    });

    test('copyWith with a change makes the change', () {
      final top = model.modules['counter']!;

      expect(model.copyWith(creator: 'x').creator, 'x');
      expect(model.copyWith(modules: const {}).modules, isEmpty);
      expect(top.copyWith(name: 'renamed').name, 'renamed');
      expect(
        top.copyWith(
          attributes: const {},
          ports: const {},
          cells: const {},
          nets: const {},
        ),
        isNot(top),
      );
      expect(
        top.cells['ff']!
            .copyWith(
              name: 'ff2',
              type: r'$dffe',
              parameters: const {},
              attributes: const {},
              portDirections: const {},
              connections: const {},
              hideName: true,
            )
            .type,
        r'$dffe',
      );
      expect(
        top.nets['count']!
            .copyWith(
              name: 'n',
              bits: const [],
              attributes: const {},
              hideName: true,
            )
            .width,
        0,
      );
      expect(
        top.ports['q']!
            .copyWith(
              name: 'p',
              direction: PortDirection.input,
              bits: const [NetBit(9)],
            )
            .direction,
        PortDirection.input,
      );
    });

    test('toString names each part, for diagnostics', () {
      final top = model.modules['counter']!;

      expect(model.toString(), contains('Yosys 0.40'));
      expect(top.toString(), contains('counter'));
      expect(top.cells['ff'].toString(), contains(r'$dff'));
      expect(top.nets['count'].toString(), contains('width: 2'));
      expect(top.ports['q'].toString(), contains('output'));
    });
  });

  group('which module is a black box', () {
    for (final (key, encoding, isBlackBox) in <(String, Object?, bool)>[
      ('blackbox', '00000000000000000000000000000001', true),
      ('blackbox', '00000001', true),
      ('blackbox', '1', true),
      ('blackbox', 1, true),
      ('whitebox', '1', true),
      ('blackbox', '00000000', false),
      ('blackbox', '0', false),
      ('blackbox', '', false),
      ('keep', '1', false),
    ]) {
      final verdict = isBlackBox ? '' : 'not ';
      test(
        '$key: ${jsonEncode(encoding)} is ${verdict}a black box',
        () {
          final model = _parseOk(
            jsonEncode({
              'modules': {
                'm': {
                  'attributes': {key: encoding},
                },
              },
            }),
          );
          expect(model.modules['m']!.isBlackBox, isBlackBox);
        },
      );
    }

    test('a module with no attributes is not a black box', () {
      final model = _parseOk('{"modules":{"m":{}}}');
      expect(model.modules['m']!.isBlackBox, isFalse);
    });
  });

  group('which module is the top', () {
    for (final (encoding, isTop) in <(Object?, bool)>[
      ('00000001', true),
      ('00000000000000000000000000000001', true),
      ('1', true),
      (1, true),
      ('00000000', false),
      ('0', false),
      (0, false),
      ('', false),
      (null, false),
    ]) {
      test('top: ${jsonEncode(encoding)} is ${isTop ? '' : 'not '}the top', () {
        final model = _parseOk(
          jsonEncode({
            'modules': {
              'm': {
                'attributes': {'top': encoding},
              },
            },
          }),
        );
        expect(model.modules['m']!.isTop, isTop);
        expect(model.topModule?.name, isTop ? 'm' : null);
      });
    }
  });
}

enum _Outcome { parsed, rejected }

/// Parse [raw] and say how it ended. Anything thrown that is not a
/// [YosysJsonParseException] fails the test with its type — that is the
/// escape this file exists to catch.
_Outcome _outcome(String raw) {
  try {
    const YosysJsonParser().parse(raw);
    return _Outcome.parsed;
  } on YosysJsonParseException catch (e) {
    expect(e, isA<Exception>(), reason: 'an `on Exception` must catch it');
    expect(e.message, isNotEmpty);
    return _Outcome.rejected;
  } on Object catch (e) {
    fail('escaped the parser as ${e.runtimeType}');
  }
}

NetlistModel _parseOk(String raw) {
  expect(_outcome(raw), _Outcome.parsed);
  return const YosysJsonParser().parse(raw);
}

String _deep(int depth) => '${'[' * depth}${']' * depth}';

String _cells(String cells) => '{"modules":{"top":{"cells":$cells}}}';

String _ports(String ports) => '{"modules":{"top":{"ports":$ports}}}';

String _nets(String nets) => '{"modules":{"top":{"netnames":$nets}}}';

String _bits(String bits) =>
    _cells('{"c":{"type":"x","connections":{"A":$bits}}}');

Map<String, Object?> _top(Map<String, Object?> doc) =>
    (doc['modules']! as Map<String, Object?>)['counter']!
        as Map<String, Object?>;

Map<String, Object?> _port(Map<String, Object?> doc, String name) =>
    (_top(doc)['ports']! as Map<String, Object?>)[name]!
        as Map<String, Object?>;

Map<String, Object?> _cell(Map<String, Object?> doc, String name) =>
    (_top(doc)['cells']! as Map<String, Object?>)[name]!
        as Map<String, Object?>;

Map<String, Object?> _net(Map<String, Object?> doc, String name) =>
    (_top(doc)['netnames']! as Map<String, Object?>)[name]!
        as Map<String, Object?>;

/// A small counter with every kind of member the model reads: ports in
/// each direction, a parameterised flip-flop with named port directions, a
/// primitive with constant bits, and nets with attributes and generated
/// names.
Map<String, Object?> _richDocument() => <String, Object?>{
  'creator': 'Yosys 0.40',
  'modules': <String, Object?>{
    'counter': <String, Object?>{
      'attributes': <String, Object?>{
        'top': '00000000000000000000000000000001',
        'src': 'counter.v:1',
      },
      'ports': <String, Object?>{
        'clk': <String, Object?>{
          'direction': 'input',
          'bits': <Object?>[2],
        },
        'q': <String, Object?>{
          'direction': 'output',
          'bits': <Object?>[3, 4],
        },
        'bus': <String, Object?>{
          'direction': 'inout',
          'bits': <Object?>[6, '1'],
        },
      },
      'cells': <String, Object?>{
        'ff': <String, Object?>{
          'hide_name': 0,
          'type': r'$dff',
          'parameters': <String, Object?>{'WIDTH': '00000010'},
          'attributes': <String, Object?>{'src': 'counter.v:7'},
          'port_directions': <String, Object?>{
            'CLK': 'input',
            'D': 'input',
            'Q': 'output',
          },
          'connections': <String, Object?>{
            'CLK': <Object?>[2],
            'D': <Object?>[5, 4],
            'Q': <Object?>[3, 4],
          },
        },
        'inv': <String, Object?>{
          'hide_name': 1,
          'type': r'$not',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
          'connections': <String, Object?>{
            'A': <Object?>['0', 'x'],
            'Y': <Object?>[5, 'z'],
          },
        },
      },
      'netnames': <String, Object?>{
        'count': <String, Object?>{
          'hide_name': 0,
          'bits': <Object?>[3, 4],
          'attributes': <String, Object?>{'src': 'counter.v:3'},
        },
        r'$auto$next': <String, Object?>{
          'hide_name': 1,
          'bits': <Object?>[5, 4],
          'attributes': <String, Object?>{},
        },
      },
    },
    'leaf': <String, Object?>{
      'attributes': <String, Object?>{},
      'ports': <String, Object?>{},
      'cells': <String, Object?>{},
      'netnames': <String, Object?>{},
    },
  },
};
