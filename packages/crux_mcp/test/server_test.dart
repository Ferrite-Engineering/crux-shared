// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

Map<String, Object?> _decode(String? line) =>
    jsonDecode(line!) as Map<String, Object?>;

String _call(int id, String tool, Object? arguments, {Object? meta}) =>
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': tool,
        'arguments': arguments,
        '_meta': ?meta,
      },
    });

/// The document text in a tools/call answer.
Map<String, Object?> _document(Map<String, Object?> answer) {
  final result = answer['result']! as Map<String, Object?>;
  final content = result['content']! as List<Object?>;
  final text = (content.single! as Map<String, Object?>)['text']! as String;
  return jsonDecode(text) as Map<String, Object?>;
}

/// Hostile path arguments: each names a file outside the root by another
/// route. Any of them reaching the runner is a file outside the root opened.
List<Map<String, Object?>> _hostileCalls(String outside) => [
  <String, Object?>{'file': p.join(outside, 'secret.sv')},
  <String, Object?>{'file': '../outside/secret.sv'},
  // The link out of the root is made only where links need no privilege.
  if (!Platform.isWindows) <String, Object?>{'file': 'escape/secret.sv'},
  <String, Object?>{'file': 'missing/../../outside/secret.sv'},
  <String, Object?>{'file': r'\\server\share\secret.sv'},
];

/// The oracle: every hostile call that reached [build]'s runner.
Future<List<String>> _leaks(
  McpServer Function(List<McpCall> calls) build,
  String outside,
) async {
  final leaks = <String>[];
  var id = 1;
  for (final arguments in _hostileCalls(outside)) {
    final calls = <McpCall>[];
    final server = build(calls);
    final answer = _decode(
      await server.handleLine(_call(id++, 'inspect', arguments)),
    );
    final doc = _document(answer);
    if (calls.isNotEmpty || doc['outcome'] != 'usage_error') {
      leaks.add('${arguments['file']} reached the runner');
    }
  }
  return leaks;
}

void main() {
  late Directory sandbox;
  late String root;
  late String outside;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('crux_mcp_server_');
    root = p.join(sandbox.path, 'root');
    outside = p.join(sandbox.path, 'outside');
    Directory(root).createSync();
    Directory(outside).createSync();
    File(p.join(root, 'a.vcd')).writeAsStringSync('');
    File(p.join(outside, 'secret.sv')).writeAsStringSync('');
    if (!Platform.isWindows) {
      Link(p.join(root, 'escape')).createSync(outside);
    }
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  group('construction', () {
    test('instructions are required and at most 600 characters', () {
      McpServer make(String instructions, [List<McpTool>? tools]) => McpServer(
        program: fixtureProgram,
        instructions: instructions,
        tools: tools ?? fixtureTools,
        confinement: Confinement(root),
        runner: recordingRunner(<McpCall>[]),
      );
      expect(() => make(''), throwsArgumentError);
      expect(() => make('x' * 601), throwsArgumentError);
      expect(make('x' * 600).instructions.length, 600);
      expect(
        () => make('x', <McpTool>[fixtureTools[0], fixtureTools[0]]),
        throwsArgumentError,
      );
    });
  });

  group('methods', () {
    test('initialize answers the asked revision, else the newest', () async {
      final server = fixtureServer(root: root);
      for (final asked in kMcpProtocolVersions) {
        final answer = _decode(
          await server.handleLine(
            '{"jsonrpc":"2.0","id":1,"method":"initialize",'
            '"params":{"protocolVersion":"$asked"}}',
          ),
        );
        expect(
          (answer['result']! as Map<String, Object?>)['protocolVersion'],
          asked,
        );
      }
      final answer = _decode(
        await server.handleLine(
          '{"jsonrpc":"2.0","id":2,"method":"initialize",'
          '"params":{"protocolVersion":"1999-01-01"}}',
        ),
      );
      expect(answer, <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'result': <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{'tools': <String, Object?>{}},
          'serverInfo': <String, Object?>{
            'name': 'fixture',
            'version': '0.0.1',
          },
          'instructions': fixtureInstructions,
        },
      });
    });

    test('ping, tools/list and the error codes', () async {
      final server = fixtureServer(root: root);
      expect(
        await server.handleLine('{"jsonrpc":"2.0","id":"a","method":"ping"}'),
        '{"jsonrpc":"2.0","id":"a","result":{}}',
      );
      final list = _decode(
        await server.handleLine(
          '{"jsonrpc":"2.0","id":1,"method":"tools/list"}',
        ),
      );
      expect(
        (list['result']! as Map<String, Object?>)['tools'],
        jsonDecode(jsonEncode(server.definitions())),
      );
      int code(String? line) =>
          (_decode(line)['error']! as Map<String, Object?>)['code']! as int;
      expect(
        code(await server.handleLine('{"jsonrpc":"2.0","id":1,"method":"x"}')),
        -32601,
      );
      expect(code(await server.handleLine('{oops')), -32700);
      expect(code(await server.handleLine('[1]')), -32600);
      expect(code(await server.handleLine('{"jsonrpc":"2.0","id":1}')), -32600);
      expect(
        code(
          await server.handleLine(
            '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}',
          ),
        ),
        -32602,
      );
      expect(
        code(
          await server.handleLine(
            '{"jsonrpc":"2.0","id":1,"method":"tools/call"}',
          ),
        ),
        -32602,
      );
      expect(code(await server.handleLine(_call(1, 'nope', null))), -32602);
      expect(await server.handleLine('{"method":"notifications/x"}'), isNull);
      expect(await server.handleLine('   '), isNull);
    });

    test('a call runs the command and returns its text unchanged', () async {
      final calls = <McpCall>[];
      final server = fixtureServer(root: root, calls: calls);
      final answer = _decode(
        await server.handleLine(_call(4, 'inspect', {'file': 'a.vcd'})),
      );
      final result = answer['result']! as Map<String, Object?>;
      expect(result['isError'], isFalse);
      final text =
          ((result['content']! as List<Object?>).single!
                  as Map<String, Object?>)['text']!
              as String;
      expect(
        text,
        McpDocument(
          tool: fixtureProgram,
          command: 'inspect',
          outcome: McpOutcome.completed,
          body: <String, Object?>{
            'argv': <String>[p.join(root, 'a.vcd')],
          },
        ).render(),
      );
      expect(calls.single.arguments.argv, <String>[p.join(root, 'a.vcd')]);
    });

    test('a bad argument is a usage_error document; nothing runs', () async {
      final calls = <McpCall>[];
      final server = fixtureServer(root: root, calls: calls);
      final answer = _decode(
        await server.handleLine(_call(1, 'inspect', {'bogus': true})),
      );
      expect((answer['result']! as Map<String, Object?>)['isError'], isTrue);
      final doc = _document(answer);
      expect(doc['outcome'], 'usage_error');
      expect(doc['command'], 'inspect');
      expect(doc['body'], isNull);
      expect(
        (doc['diagnostics']! as List<Object?>).single,
        <String, Object?>{
          'severity': 'error',
          'code': 'usage',
          'message': 'unknown field `bogus` for inspect',
          'fix': null,
          'location': null,
        },
      );
      expect(calls, isEmpty);
    });

    test('an engine_error document is an error result', () async {
      final server = fixtureServer(
        root: root,
        runner: (call) async => McpCommandOutput.document(
          McpDocument(
            tool: fixtureProgram,
            command: call.tool.name,
            outcome: McpOutcome.engineError,
            diagnostics: const <McpDiagnostic>[
              McpDiagnostic.error('engine.missing', 'no engine'),
            ],
          ),
        ),
      );
      final answer = _decode(
        await server.handleLine(_call(1, 'inspect', {'file': 'a.vcd'})),
      );
      expect((answer['result']! as Map<String, Object?>)['isError'], isTrue);
      expect(_document(answer)['outcome'], 'engine_error');
    });

    test('a runner that throws is an internal error, said on stderr', () async {
      final logged = <String>[];
      final server = fixtureServer(
        root: root,
        log: logged.add,
        runner: (_) async => throw StateError('boom'),
      );
      final answer = _decode(
        await server.handleLine(_call(1, 'inspect', {'file': 'a.vcd'})),
      );
      expect((answer['error']! as Map<String, Object?>)['code'], -32603);
      expect(logged.single, contains('boom'));
    });

    test('the files a project names are checked before the run', () async {
      final calls = <McpCall>[];
      final tool = McpTool(
        name: 'lint',
        description: 'Lint a project.',
        fields: const <McpField>[
          McpField('project', kind: McpFieldKind.path),
        ],
        required: const <String>['project'],
        checkNamedFiles: (arguments, confinement) =>
            confinement.confineAll(<String>['ok.sv', '../outside/secret.sv']),
      );
      final server = fixtureServer(
        root: root,
        calls: calls,
        tools: <McpTool>[tool],
      );
      final answer = _decode(
        await server.handleLine(_call(1, 'lint', {'project': 'a.vcd'})),
      );
      expect(_document(answer)['outcome'], 'usage_error');
      expect(calls, isEmpty);
    });
  });

  group('confinement', () {
    test('no path outside the root reaches the runner', () async {
      expect(
        await _leaks(
          (calls) => fixtureServer(root: root, calls: calls),
          outside,
        ),
        isEmpty,
      );
    });

    test('mutation: a confinement that admits everything is caught', () async {
      final leaks = await _leaks(
        (calls) => fixtureServer(
          root: root,
          calls: calls,
          confinement: Confinement.withRule(root, (_, _) => null),
        ),
        outside,
      );
      expect(leaks, isNotEmpty);
    });
  });

  group('stdio', () {
    test('a line past 4 MiB is refused and the next line answered', () async {
      final client = McpScriptedClient.inProcess(fixtureServer(root: root))
        ..sendBytes(<int>[
          ...List<int>.filled(kMcpMaxLineBytes, 0x20),
          0x0A,
        ]);
      expect(_decode(await client.next()), <String, Object?>{
        'jsonrpc': '2.0',
        'id': null,
        'error': <String, Object?>{
          'code': -32600,
          'message': 'request line too long',
        },
      });
      expect((await client.request('ping'))['result'], <String, Object?>{});
      await client.close();
    });

    test(
      'a line of exactly the limit, its newline included, is read',
      () async {
        const ping = '{"jsonrpc":"2.0","id":9,"method":"ping"}';
        // Padding with spaces keeps the line valid JSON.
        final client = McpScriptedClient.inProcess(fixtureServer(root: root))
          ..sendBytes(<int>[
            ...utf8.encode(ping),
            ...List<int>.filled(kMcpMaxLineBytes - ping.length - 1, 0x20),
            0x0A,
          ]);
        expect(_decode(await client.next())['id'], 9);
        await client.close();
      },
    );

    test('a line that is not UTF-8 is a parse error', () async {
      final client = McpScriptedClient.inProcess(fixtureServer(root: root))
        ..sendBytes(<int>[0xFF, 0xFE, 0x0A]);
      expect(
        (_decode(await client.next())['error']!
            as Map<String, Object?>)['code'],
        -32700,
      );
      await client.close();
    });

    test('a last line with no newline is still answered', () async {
      final client = McpScriptedClient.inProcess(fixtureServer(root: root))
        ..sendBytes(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"ping"}'));
      final closed = client.close();
      expect(_decode(await client.next())['id'], 1);
      await closed;
    });

    test('a print from a runner never reaches the protocol', () async {
      final logged = <String>[];
      final client = McpScriptedClient.inProcess(
        fixtureServer(
          root: root,
          log: logged.add,
          runner: (call) async {
            // The point of the test: a runner that prints.
            // ignore: avoid_print
            print('chatter');
            return await recordingRunner(<McpCall>[])(call);
          },
        ),
      )..send(_call(1, 'inspect', {'file': 'a.vcd'}));
      expect(_decode(await client.next())['id'], 1);
      expect(logged, <String>['chatter']);
      await client.close();
    });

    test('a cancelled call is not answered; the next one is', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var sawCancel = false;
      final client = McpScriptedClient.inProcess(
        fixtureServer(
          root: root,
          runner: (call) async {
            if (!started.isCompleted) {
              started.complete();
              await Future.any(<Future<void>>[
                call.whenCancelled,
                release.future,
              ]);
              sawCancel = call.isCancelled;
            }
            return await recordingRunner(<McpCall>[])(call);
          },
        ),
      )..send(_call(1, 'inspect', {'file': 'a.vcd'}));
      await started.future;
      client
        ..send(
          '{"jsonrpc":"2.0","method":"notifications/cancelled",'
          '"params":{"requestId":1}}',
        )
        ..send('{"jsonrpc":"2.0","id":2,"method":"ping"}');
      expect(_decode(await client.next())['id'], 2);
      expect(sawCancel, isTrue);
      await client.close();
    });

    test('a call cancelled before it starts never runs', () async {
      final calls = <McpCall>[];
      final gate = Completer<void>();
      var first = true;
      final client =
          McpScriptedClient.inProcess(
              fixtureServer(
                root: root,
                runner: (call) async {
                  if (first) {
                    first = false;
                    await gate.future;
                  }
                  return await recordingRunner(calls)(call);
                },
              ),
            )
            ..send(_call(1, 'inspect', {'file': 'a.vcd'}))
            ..send(_call(2, 'inspect', {'file': 'a.vcd'}))
            ..send(
              '{"jsonrpc":"2.0","method":"notifications/cancelled",'
              '"params":{"requestId":2}}',
            )
            ..send(
              '{"jsonrpc":"2.0","method":"notifications/cancelled",'
              '"params":{"requestId":99}}',
            )
            ..send('{"jsonrpc":"2.0","id":3,"method":"ping"}');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      expect(_decode(await client.next())['id'], 1);
      expect(_decode(await client.next())['id'], 3);
      expect(calls, hasLength(1));
      await client.close();
    });

    test('progress goes out only for a call that asked for it', () async {
      final client =
          McpScriptedClient.inProcess(
            fixtureServer(
              root: root,
              runner: (call) async {
                call.progress(1, total: 2, message: 'half');
                return await recordingRunner(<McpCall>[])(call);
              },
            ),
          )..send(
            _call(
              1,
              'inspect',
              {'file': 'a.vcd'},
              meta: {'progressToken': 't'},
            ),
          );
      expect(_decode(await client.next()), <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        'params': <String, Object?>{
          'progressToken': 't',
          'progress': 1,
          'total': 2,
          'message': 'half',
        },
      });
      expect(_decode(await client.next())['id'], 1);
      client.send(_call(2, 'inspect', {'file': 'a.vcd'}));
      expect(_decode(await client.next())['id'], 2);
      await client.close();
    });
  });

  group('telemetry', () {
    test('one event per call of a served tool, and no names', () async {
      final events = <(String, Map<String, Object?>)>[];
      final telemetry = McpTelemetry(
        consented: () => true,
        sink: (e, props) => events.add((e, props)),
        environment: const <String, String>{},
      );
      final server = fixtureServer(root: root, telemetry: telemetry);
      await server.handleLine(_call(1, 'inspect', {'file': 'a.vcd'}));
      await server.handleLine(_call(2, 'inspect', {'file': '/etc/passwd'}));
      await server.handleLine(_call(3, '/home/x/secret', null));
      expect(events, hasLength(2));
      expect(events[0].$1, 'mcp.tool_call');
      expect(events[0].$2, <String, Object?>{
        'tool': 'inspect',
        'outcome': 'completed',
        'duration': 'lt_1s',
      });
      expect(events[1].$2['outcome'], 'usage_error');
    });

    test('a crash and an unreadable output are counted as such', () async {
      final events = <Map<String, Object?>>[];
      final telemetry = McpTelemetry(
        consented: () => true,
        sink: (_, props) => events.add(props),
        environment: const <String, String>{},
      );
      await fixtureServer(
        root: root,
        telemetry: telemetry,
        runner: (_) async => throw StateError('x'),
      ).handleLine(_call(1, 'inspect', {'file': 'a.vcd'}));
      await fixtureServer(
        root: root,
        telemetry: telemetry,
        runner: (_) async => McpCommandOutput.text('not json'),
      ).handleLine(_call(1, 'inspect', {'file': 'a.vcd'}));
      expect(events.map((e) => e['outcome']), <String>[
        'crashed',
        'unreadable',
      ]);
    });
  });
}
