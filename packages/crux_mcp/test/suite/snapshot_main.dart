// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Writes the definition snapshots `suite_budget_test.dart` measures: what
/// each server binary sends an agent host before any tool runs, its
/// `instructions` paragraph and its `tools/list`.
///
/// Run through `tool/mcp-suite-snapshot.sh`, which names the binaries:
///
///     dart run test/suite/snapshot_main.dart <out-dir> \
///         <name> <executable> "<arguments before --root>" [--redact <word>] \
///         ...
///
/// Each server is started with its arguments, `--root` at an empty temporary
/// directory, and `CI` set (so no binary sends telemetry); it is asked
/// `initialize` and `tools/list`, then its input is closed. The snapshot is
/// `<out-dir>/<name>.json`: the name, the instructions and every tool's
/// `name`, `description` and `inputSchema` as the server sent them.
///
/// `--redact <word>` replaces each occurrence of `<word>` in the text, in any
/// letter case, with as many `x` characters, so a server's own name can be
/// kept out of this public repository without changing a single count.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:path/path.dart' as p;

import 'suite_snapshot.dart';

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
      'usage: snapshot_main.dart <out-dir> '
      '<name> <executable> <arguments> [--redact <word>] ...',
    );
    exitCode = 2;
    return;
  }
  final outDir = Directory(args.first)..createSync(recursive: true);
  var i = 1;
  while (i < args.length) {
    if (i + 2 >= args.length) {
      stderr.writeln('incomplete server after ${args[i]}');
      exitCode = 2;
      return;
    }
    final name = args[i];
    final executable = args[i + 1];
    final arguments = args[i + 2]
        .split(' ')
        .where((a) => a.isNotEmpty)
        .toList();
    i += 3;
    String? redact;
    if (i + 1 < args.length && args[i] == '--redact') {
      redact = args[i + 1];
      i += 2;
    }
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(name)) {
      stderr.writeln(
        'server name `$name`: lower case letters, digits, - and _',
      );
      exitCode = 2;
      return;
    }
    final snapshot = await _capture(name, executable, arguments);
    var text = '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n';
    if (redact != null && redact.isNotEmpty) {
      text = text.replaceAll(
        RegExp(RegExp.escape(redact), caseSensitive: false),
        'x' * redact.length,
      );
    }
    final file = File(p.join(outDir.path, '$name.json'))
      ..writeAsStringSync(text);
    stdout.writeln('wrote ${file.path}');
  }
  var total = 0;
  for (final snapshot in SuiteSnapshot.loadDirectory(outDir.path)) {
    stdout.writeln(snapshot.summary());
    total += snapshot.length;
  }
  stdout.writeln('suite total $total of $kMcpSuiteDefinitionCeiling');
}

Future<Map<String, Object?>> _capture(
  String name,
  String executable,
  List<String> arguments,
) async {
  final root = Directory.systemTemp.createTempSync('crux_mcp_snapshot_');
  try {
    final client = await McpScriptedClient.start(
      executable,
      <String>[...arguments, '--root', root.path],
      environment: <String, String>{'CI': 'true'},
    );
    final init = await client.request('initialize', <String, Object?>{
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{'name': 'snapshot', 'version': '1'},
    });
    final listed = await client.request('tools/list');
    final code = await client.close();
    if (code != 0) {
      throw StateError(
        '$name exited $code:\n${client.stderrLines.join('\n')}',
      );
    }
    final initResult = init['result']! as Map<String, Object?>;
    final tools =
        (listed['result']! as Map<String, Object?>)['tools']! as List<Object?>;
    return <String, Object?>{
      'server': name,
      'instructions': initResult['instructions'] ?? '',
      'tools': <Object?>[
        for (final tool in tools.cast<Map<String, Object?>>())
          <String, Object?>{
            'name': tool['name'],
            'description': tool['description'],
            'inputSchema': tool['inputSchema'],
          },
      ],
    };
  } finally {
    root.deleteSync(recursive: true);
  }
}
