// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Directory sandbox;
  late Confinement confinement;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('crux_mcp_tool_');
    File(p.join(sandbox.path, 'a.vcd')).writeAsStringSync('');
    confinement = Confinement(sandbox.path);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  final inspect = fixtureTools[0];

  McpArguments ok(Object? arguments) {
    final r = inspect.check(arguments, confinement);
    if (r is McpArgumentError) fail(r.message);
    return r as McpArguments;
  }

  String refused(Object? arguments, [McpTool? tool]) {
    final r = (tool ?? inspect).check(arguments, confinement);
    expect(r, isA<McpArgumentError>(), reason: '$arguments');
    return (r as McpArgumentError).message;
  }

  group('definition', () {
    test('the input schema is generated from the fields, in order', () {
      // Written by hand from the field table above.
      expect(
        mcpRenderJsonLine(inspect.definition()),
        <String>[
          '{"name":"inspect","description":"Inspect one file.",',
          '"inputSchema":{"type":"object","properties":{',
          '"file":{"type":"string"},',
          '"depth":{"type":"integer"},',
          '"verbose":{"type":"boolean"},',
          '"at":{"type":["integer","string"],',
          '"description":"A tick, or a time such as 1500ns."},',
          '"names":{"type":"array","items":{"type":"string"}},',
          '"mode":{"type":"string"}},',
          '"required":["file"]}}',
        ].join(),
      );
    });

    test('an empty required list is still sent', () {
      final scan = fixtureTools[1].definition();
      expect(
        (scan['inputSchema']! as Map<String, Object?>)['required'],
        isEmpty,
      );
    });

    test('the definition length is its compact JSON', () {
      expect(
        inspect.definitionLength,
        mcpRenderJsonLine(inspect.definition()).length,
      );
    });

    test('a malformed table is refused', () {
      McpTool make(List<McpField> fields, [List<String> req = const []]) =>
          McpTool(name: 't', description: 'd', fields: fields, required: req);
      expect(
        () => McpTool(name: 'Bad', description: 'd', fields: const []),
        throwsArgumentError,
      );
      expect(
        () => make(const [
          McpField('a', kind: McpFieldKind.text),
          McpField('a', kind: McpFieldKind.text),
        ]),
        throwsArgumentError,
      );
      expect(
        () => make(const [McpField('b', kind: McpFieldKind.boolean)]),
        throwsArgumentError,
      );
      expect(
        () => make(const [
          McpField('n', kind: McpFieldKind.integer, minimum: -1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => make(const [McpField('a', kind: McpFieldKind.text)], ['z']),
        throwsArgumentError,
      );
      expect(make(const []).command, 't');
    });
  });

  group('arguments', () {
    test('become flags in field order, then positional arguments', () {
      final args = ok(<String, Object?>{
        'mode': 'fast',
        'names': <Object?>['top.a', 'top.b'],
        'verbose': true,
        'at': '1.5us',
        'depth': 2,
        'file': 'a.vcd',
      });
      final file = p.join(sandbox.path, 'a.vcd');
      expect(args.argv, <String>[
        '--depth',
        '2',
        '--verbose',
        '--at',
        '1.5us',
        '--name',
        'top.a',
        '--name',
        'top.b',
        '--mode',
        'fast',
        file,
      ]);
      expect(args.values['file'], file);
      expect(args.values['names'], <Object?>['top.a', 'top.b']);
    });

    test('false passes nothing; a tick count passes as text', () {
      final args = ok(<String, Object?>{
        'file': 'a.vcd',
        'verbose': false,
        'at': 0,
      });
      expect(args.argv, <String>['--at', '0', p.join(sandbox.path, 'a.vcd')]);
    });

    test('a list of paths is held inside the root item by item', () {
      final scan = fixtureTools[1];
      final r = scan.check(<String, Object?>{
        'paths': <Object?>['a.vcd', 'b.vcd'],
        'include': <Object?>['.'],
      }, confinement);
      expect((r as McpArguments).argv, <String>[
        '-I',
        p.join(sandbox.path, '.'),
        p.join(sandbox.path, 'a.vcd'),
        p.join(sandbox.path, 'b.vcd'),
      ]);
      expect(
        refused(<String, Object?>{
          'paths': <Object?>['a.vcd', '../x'],
        }, scan),
        contains('outside the root'),
      );
    });

    test('refusals, each with its own message', () {
      expect(refused(<Object?>[1]), 'the arguments are one object');
      expect(refused('x'), 'the arguments are one object');
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'bogus': 1}),
        'unknown field `bogus` for inspect',
      );
      expect(refused(null), '`file` is required for inspect');
      expect(refused(<String, Object?>{}), '`file` is required for inspect');
      expect(refused(<String, Object?>{'file': 3}), '`file` is text');
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'depth': 0}),
        '`depth` is a whole number, 1 or more',
      );
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'depth': 1.0}),
        '`depth` is a whole number, 1 or more',
      );
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'verbose': 'yes'}),
        '`verbose` is true or false',
      );
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'names': 'top.a'}),
        '`names` is a list',
      );
      expect(
        refused(<String, Object?>{
          'file': 'a.vcd',
          'names': <Object?>[1],
        }),
        '`names` is text',
      );
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'mode': '--rm'}),
        '`--rm` is not a valid value for mode',
      );
      expect(
        refused(<String, Object?>{'file': 'a.vcd', 'mode': ''}),
        '`` is not a valid value for mode',
      );
      for (final at in <Object?>[-1, '1.5', '1500 ns', 'ns', 1.5, '-3']) {
        expect(
          refused(<String, Object?>{'file': 'a.vcd', 'at': at}),
          '`at` is a tick count or a time such as 1500ns',
          reason: '$at',
        );
      }
      expect(
        refused(<String, Object?>{'file': '/etc/passwd'}),
        contains('outside the root'),
      );
    });

    test('values: an enum in the schema, and any other value is refused', () {
      final pick = McpTool(
        name: 'pick',
        description: 'd',
        fields: const [
          McpField(
            'kind',
            kind: McpFieldKind.text,
            flag: '--kind',
            values: ['cell', 'net'],
          ),
        ],
      );
      // Written by hand: type first, then enum, as the contract shows.
      expect(
        mcpRenderJsonLine(pick.definition()),
        '{"name":"pick","description":"d","inputSchema":{"type":"object",'
        '"properties":{"kind":{"type":"string","enum":["cell","net"]}},'
        '"required":[]}}',
      );
      final good = pick.check(<String, Object?>{'kind': 'net'}, confinement);
      expect((good as McpArguments).argv, <String>['--kind', 'net']);
      expect(
        refused(<String, Object?>{'kind': 'port'}, pick),
        '`--kind port` is not cell or net',
      );
      expect(
        refused(<String, Object?>{'kind': 'Cell'}, pick),
        '`--kind Cell` is not cell or net',
      );
      expect(
        refused(<String, Object?>{'kind': '--rm'}, pick),
        '`--rm` is not a valid value for kind',
      );
      const bads = <List<McpField>>[
        [McpField('a', kind: McpFieldKind.text, values: [])],
        [
          McpField('a', kind: McpFieldKind.text, values: ['x', 'x']),
        ],
        [
          McpField('a', kind: McpFieldKind.text, values: ['-x']),
        ],
        [
          McpField('a', kind: McpFieldKind.path, values: ['x']),
        ],
      ];
      for (final bad in bads) {
        expect(
          () => McpTool(name: 't', description: 'd', fields: bad),
          throwsArgumentError,
        );
      }
    });

    test('an unknown field is reported before a missing one', () {
      expect(
        refused(<String, Object?>{'bogus': 1}),
        'unknown field `bogus` for inspect',
      );
    });
  });
}
