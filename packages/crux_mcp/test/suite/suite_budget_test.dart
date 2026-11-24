// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';
import 'suite_snapshot.dart';

/// The servers an agent host carries when every server in the suite is
/// registered: the four products' servers in their Pro editions (a superset
/// of each open core's tools) and the reference server.
const List<String> _servers = <String>[
  'lintcrux',
  'netcrux',
  'reference',
  'simcrux',
  'wavecrux',
];

final String _snapshots = p.join('test', 'suite', 'snapshots');

/// A tool with no fields, as `tools/list` sends it.
Map<String, Object?> _tool(String name, int descriptionLength) =>
    <String, Object?>{
      'name': name,
      'description': 'd' * descriptionLength,
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'required': <Object?>[],
      },
    };

/// The compact definition of [_tool], counted by hand: `{"name":"N",
/// "description":"D","inputSchema":{"type":"object","properties":{},
/// "required":[]}}` is 90 characters around the name and the description.
int _length(String name, int descriptionLength) =>
    90 + name.length + descriptionLength;

void main() {
  final snapshots = SuiteSnapshot.loadDirectory(_snapshots);

  group('the measure', () {
    test('a tool counts its compact JSON', () {
      expect(SuiteSnapshot.toolLength(_tool('t', 10)), _length('t', 10));
    });

    test('a server counts its tools and its instructions', () {
      final snapshot = SuiteSnapshot('s', 'i' * 7, <Map<String, Object?>>[
        _tool('a', 100),
        _tool('b', 200),
      ]);
      expect(snapshot.length, _length('a', 100) + _length('b', 200) + 7);
    });

    test(
      'a snapshot counts what this package counts for the same server',
      () async {
        final server = fixtureServer(root: '.');
        final client = McpScriptedClient.inProcess(server);
        final init = await client.request('initialize');
        final listed = await client.request('tools/list');
        await client.close();
        final result = init['result']! as Map<String, Object?>;
        final tools =
            (listed['result']! as Map<String, Object?>)['tools']!
                as List<Object?>;
        final snapshot = SuiteSnapshot(
          'fixture',
          result['instructions']! as String,
          tools.cast<Map<String, Object?>>(),
        );
        expect(snapshot.length, mcpServerDefinitionLength(server));
        for (var i = 0; i < server.tools.length; i++) {
          expect(
            SuiteSnapshot.toolLength(snapshot.tools[i]),
            server.tools[i].definitionLength,
          );
        }
      },
    );

    test('one character past each ceiling fails', () {
      final atTool = _tool('t', 2000 - _length('t', 0));
      expect(
        suiteBudgetProblems(<SuiteSnapshot>[
          SuiteSnapshot('s', '', <Map<String, Object?>>[atTool]),
        ]),
        isEmpty,
      );
      expect(
        suiteBudgetProblems(<SuiteSnapshot>[
          SuiteSnapshot('s', '', <Map<String, Object?>>[
            _tool('t', 2001 - _length('t', 0)),
          ]),
        ]),
        <String>['s: tool `t` takes 2001 characters, past 2000'],
      );

      final fullServer = SuiteSnapshot('s', 'i' * 2000, <Map<String, Object?>>[
        atTool,
      ]);
      expect(suiteBudgetProblems(<SuiteSnapshot>[fullServer]), isEmpty);
      expect(
        suiteBudgetProblems(<SuiteSnapshot>[
          SuiteSnapshot('s', 'i' * 2001, <Map<String, Object?>>[atTool]),
        ]),
        <String>['s takes 4001 characters with its instructions, past 4000'],
      );

      final four = List<SuiteSnapshot>.filled(4, fullServer);
      expect(suiteBudgetProblems(four), isEmpty);
      expect(
        suiteBudgetProblems(<SuiteSnapshot>[
          ...four,
          const SuiteSnapshot('s', 'i', <Map<String, Object?>>[]),
        ]),
        <String>['the suite takes 16001 characters, past 16000'],
      );
    });
  });

  group('the suite as its binaries send it', () {
    test('every server has a snapshot, and only those', () {
      expect(snapshots.map((s) => s.server), _servers);
      for (final snapshot in snapshots) {
        expect(snapshot.tools, isNotEmpty, reason: snapshot.server);
        final names = snapshot.tools.map((t) => t['name']).toList();
        expect(names.toSet(), hasLength(names.length), reason: snapshot.server);
      }
    });

    test('each snapshot is a definition only: name, description, '
        'inputSchema', () {
      for (final snapshot in snapshots) {
        for (final tool in snapshot.tools) {
          expect(tool.keys, <String>[
            'name',
            'description',
            'inputSchema',
          ], reason: '${snapshot.server} ${jsonEncode(tool['name'])}');
          expect(tool['name'], isA<String>());
          expect(tool['description'], isA<String>());
          expect(
            (tool['inputSchema']! as Map<String, Object?>)['type'],
            'object',
          );
        }
      }
    });

    test('2,000 a tool, 4,000 a server, 16,000 together', () {
      expect(
        suiteBudgetProblems(snapshots),
        isEmpty,
        reason: snapshots.map((s) => s.summary()).join('\n'),
      );
    });
  });
}
