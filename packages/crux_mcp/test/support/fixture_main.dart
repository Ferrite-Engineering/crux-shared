// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';

import 'fixture.dart';

/// The fixture server on this process's standard input and output, as a
/// product's `mcp` subcommand runs one. Its runner prints a line on every
/// call, which must reach stderr and never the protocol.
Future<void> main(List<String> args) async {
  final root = args.isEmpty ? Directory.current.path : args.first;
  final server = fixtureServer(
    root: root,
    log: stderr.writeln,
    runner: (call) async {
      // The point of the fixture: a runner that prints.
      // ignore: avoid_print
      print('fixture: running ${call.tool.name}');
      return await recordingRunner(<McpCall>[])(call);
    },
  );
  await server.serve(stdin, stdout);
  await stdout.flush();
}
