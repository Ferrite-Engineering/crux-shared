// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
@Tags(<String>['reference-live'])
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The golden transcripts against another server binary, so every server in
/// the suite, whatever its language, is held to one protocol.
///
/// `CRUX_MCP_SERVER_BIN` names the binary; `CRUX_MCP_SERVER_ARGS` its
/// arguments before `--root` (space-separated, default `mcp`). The server is
/// started with `--root` at an empty temporary directory.
///
/// When the binary is not named, which is every CI run, no test is declared
/// at all rather than one skipped per transcript: CI holds a ceiling on
/// skipped tests, and this is not CI evidence either way.
void main() {
  final binary = Platform.environment['CRUX_MCP_SERVER_BIN'];
  if (binary == null || binary.isEmpty) return;
  final args = (Platform.environment['CRUX_MCP_SERVER_ARGS'] ?? 'mcp')
      .split(' ')
      .where((a) => a.isNotEmpty)
      .toList();
  final transcripts = McpTranscript.loadDirectory(
    p.join('test', 'conformance', 'transcripts'),
  );

  for (final transcript in transcripts) {
    test(
      transcript.name,
      () async {
        final root = Directory.systemTemp.createTempSync('crux_mcp_live_');
        try {
          final client = await McpScriptedClient.start(binary, <String>[
            ...args,
            '--root',
            root.path,
          ]);
          final problems = await transcript.run(client);
          final code = await client.close();
          expect(problems, isEmpty);
          expect(code, 0, reason: client.stderrLines.join('\n'));
        } finally {
          root.deleteSync(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
