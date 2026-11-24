// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';

/// The golden transcripts, replayed against the shared server: in this
/// process, and as a child process on real standard input and output.
void main() {
  final transcripts = McpTranscript.loadDirectory(
    p.join('test', 'conformance', 'transcripts'),
  );

  test('the transcripts are there', () {
    expect(transcripts.map((t) => t.name), <String>[
      'initialize',
      'ping-and-notifications',
      'protocol-errors',
      'line-limit',
      'tools',
    ]);
  });

  group('in process', () {
    for (final transcript in transcripts) {
      test(transcript.name, () async {
        final client = McpScriptedClient.inProcess(
          fixtureServer(root: Directory.systemTemp.path),
        );
        expect(await transcript.run(client), isEmpty);
        await client.close();
      });
    }
  });

  test('over stdio, with a runner that prints', () async {
    final client = await McpScriptedClient.start(
      Platform.resolvedExecutable,
      <String>[
        p.join('test', 'support', 'fixture_main.dart'),
        Directory.systemTemp.path,
      ],
    );
    for (final transcript in transcripts) {
      expect(await transcript.run(client), isEmpty, reason: transcript.name);
    }
    // A call that runs: the runner's print reaches stderr, not stdout.
    final answer = await client.request('tools/call', <String, Object?>{
      'name': 'scan',
      'arguments': <String, Object?>{},
    });
    expect((answer['result']! as Map<String, Object?>)['isError'], isFalse);
    expect(await client.close(), 0);
    expect(client.stderrLines, contains('fixture: running scan'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('the matcher', () {
    test('wildcards, optional members and order', () {
      expect(mcpMatchPattern(r'$any', 3), isEmpty);
      expect(mcpMatchPattern(r'$string', 3), isNotEmpty);
      expect(mcpMatchPattern(r'$integer', 'x'), isNotEmpty);
      expect(mcpMatchPattern(r'$boolean', 1), isNotEmpty);
      expect(mcpMatchPattern(r'$boolean', true), isEmpty);
      expect(mcpMatchPattern({'a?': 1}, <String, Object?>{}), isEmpty);
      expect(mcpMatchPattern({'a?': 1}, {'a': 2}), isNotEmpty);
      expect(mcpMatchPattern({'a': 1}, {'a': 1, 'b': 2}), isNotEmpty);
      expect(mcpMatchPattern({'a': 1}, <String, Object?>{}), isNotEmpty);
      expect(mcpMatchPattern([1, 2], [1]), isNotEmpty);
      expect(mcpMatchPattern([1], 'x'), isNotEmpty);
      expect(mcpMatchPattern({'a': 1}, 'x'), isNotEmpty);
      expect(mcpMatchPattern(1, 2), isNotEmpty);
      expect(
        mcpMatchPattern({
          r'$json': {'a': 1, 'b': 2},
        }, '{"b":2,"a":1}'),
        isNotEmpty,
        reason: 'members inside a JSON text must come in order',
      );
      expect(
        mcpMatchPattern({
          r'$json': {'a': 1, 'b': 2},
        }, '{"a":1,"b":2}'),
        isEmpty,
      );
      expect(mcpMatchPattern({r'$json': 1}, 'nope'), isNotEmpty);
      expect(mcpMatchPattern({r'$json': 1}, 1), isNotEmpty);
      expect(mcpMatchPattern({r'$each': 1}, <Object?>[]), isNotEmpty);
      expect(mcpMatchPattern({r'$each': 1}, <Object?>[1, 2]), isNotEmpty);
      expect(
        mcpMatchPattern('{{x}}', 'v', bindings: {'x': 'v'}),
        isEmpty,
      );
    });

    test('a transcript that is not one is refused', () {
      for (final text in <String>[
        '[]',
        '{"name": "x"}',
        '{"name": "x", "steps": []}',
        '{"name": "x", "steps": [1]}',
      ]) {
        expect(() => McpTranscript.parse(text), throwsFormatException);
      }
    });
  });
}
