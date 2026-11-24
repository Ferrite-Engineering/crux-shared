// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_telemetry_core/crux_telemetry_core.dart'
    show DesktopTelemetryConsent, DesktopTelemetryStore;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

const String _id = '00000000-0000-4000-8000-00000000000a';

/// The desktop app's record, in memory.
class _Recorded implements DesktopTelemetryStore {
  _Recorded(this.values);
  final Map<String, String> values;
  @override
  String? read(String key) => values[key];
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('crux_mcp_tel'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Serves one `inspect` call through a server wired with
  /// `McpTelemetry.desktop`, ends the input, and returns what reached the
  /// Worker.
  Future<List<http.Request>> serveOneCall({
    required Map<String, String> recorded,
    Map<String, String> environment = const <String, String>{},
  }) async {
    File('${root.path}/a.sv').writeAsStringSync('module a; endmodule\n');
    final sent = <http.Request>[];
    final server = fixtureServer(
      root: root.path,
      // The one line a product writes, with the test seams added.
      telemetry: McpTelemetry.desktop(
        HeadlessTelemetry(
          product: CruxTelemetryProduct.simcrux,
          pro: false,
          appVersion: '2.0.0',
          environment: environment,
          consent: DesktopTelemetryConsent([_Recorded(recorded)]),
          client: MockClient((request) async {
            sent.add(request);
            return http.Response('', 202);
          }),
          flushDelay: const Duration(hours: 1),
        ),
        environment: environment,
      ),
    );
    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();
    final lines = <String>[];
    output.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
    final served = server.serve(input.stream, output.sink);
    input
      ..add(
        utf8.encode(
          '${jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'inspect',
              'arguments': <String, Object?>{'file': 'a.sv'},
            },
          })}\n',
        ),
      )
      ..add(utf8.encode('\n'));
    await input.close();
    await served;
    await output.close();
    expect(lines, hasLength(1), reason: 'the call was answered');
    return sent;
  }

  test('under recorded consent the call is counted, and serve sends it '
      'when its input ends', () async {
    final sent = await serveOneCall(
      recorded: <String, String>{
        'telemetry.consent': 'enabled',
        'telemetry.installationId': _id,
      },
    );
    expect(sent, hasLength(1));
    final body = jsonDecode(sent.single.body) as Map<String, Object?>;
    expect(body['installation_id'], _id);
    expect(body['product'], 'simcrux');
    expect(body['events'], <Object?>[
      <String, Object?>{
        'name': 'mcp.tool_call',
        'properties': <String, Object?>{
          'duration': 'lt_1s',
          'outcome': 'completed',
          'tool': 'inspect',
        },
        'count': 1,
      },
    ]);
    // Nothing from the call's arguments reaches the wire.
    expect(sent.single.body, isNot(contains('a.sv')));
  });

  test('no recorded consent: nothing is sent', () async {
    expect(await serveOneCall(recorded: const <String, String>{}), isEmpty);
  });

  test('CI set: nothing is sent, whatever the desktop app recorded', () async {
    expect(
      await serveOneCall(
        recorded: <String, String>{
          'telemetry.consent': 'enabled',
          'telemetry.installationId': _id,
        },
        environment: const <String, String>{'CI': 'true'},
      ),
      isEmpty,
    );
  });

  test('a close that throws does not stop serve completing', () async {
    final server = fixtureServer(
      root: root.path,
      telemetry: McpTelemetry(
        consented: () => false,
        sink: (_, _) {},
        environment: const <String, String>{},
        close: () async => throw StateError('down'),
      ),
    );
    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();
    output.stream.listen((_) {});
    final served = server.serve(input.stream, output.sink);
    await input.close();
    await served;
    await output.close();
  });
}
