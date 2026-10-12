// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A second process for the cross-process upsert test in
// `workspace_store_test.dart`: waits for a go file, then upserts [count]
// artifacts for one design, all at once.
//
// Arguments: <workspace dir> <design id> <artifact dir> <prefix> <count>
// <go file>.

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final [workspace, designId, artifactDir, prefix, countArg, goFile] = args;
  final count = int.parse(countArg);
  final store = CxpWorkspaceStore(workspaceDirectory: workspace);
  final paths = [
    for (var i = 0; i < count; i++)
      (File(p.join(artifactDir, '$prefix$i.vcd'))..writeAsStringSync('x')).path,
  ];
  stdout.writeln('ready');
  while (!File(goFile).existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  await Future.wait([
    for (final path in paths)
      store.upsertArtifact(
        designId: designId,
        kind: 'waveform',
        path: path,
        producer: prefix,
      ),
  ]);
}
