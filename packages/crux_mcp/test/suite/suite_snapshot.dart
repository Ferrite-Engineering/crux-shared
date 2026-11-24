// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:path/path.dart' as p;

/// The most characters every server in the suite may send together: each
/// tool's definition and each server's `instructions`, about 4,000 tokens,
/// the set an agent host carries when every server is registered.
const int kMcpSuiteDefinitionCeiling = 16000;

/// What one server sends an agent host before any tool runs, as
/// `snapshot_main.dart` captured it from the server's binary.
class SuiteSnapshot {
  /// A snapshot of [server]'s [instructions] and [tools].
  const SuiteSnapshot(this.server, this.instructions, this.tools);

  /// The snapshot in [file], as `snapshot_main.dart` writes it.
  factory SuiteSnapshot.load(File file) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return SuiteSnapshot(
      json['server']! as String,
      json['instructions']! as String,
      (json['tools']! as List<Object?>).cast<Map<String, Object?>>(),
    );
  }

  /// Every snapshot in [directory], by server name.
  static List<SuiteSnapshot> loadDirectory(String directory) {
    final files =
        Directory(directory)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return <SuiteSnapshot>[for (final f in files) SuiteSnapshot.load(f)];
  }

  /// The server's name, which is also its file's name.
  final String server;

  /// The `instructions` paragraph `initialize` answered with; empty when it
  /// sent none.
  final String instructions;

  /// Each tool as `tools/list` sent it: `name`, `description`,
  /// `inputSchema`.
  final List<Map<String, Object?>> tools;

  /// The characters [tool]'s definition takes: its compact JSON, as
  /// `McpTool.definitionLength` counts a tool built with this package.
  static int toolLength(Map<String, Object?> tool) => mcpRenderJsonLine(
    <String, Object?>{
      'name': tool['name'],
      'description': tool['description'],
      'inputSchema': tool['inputSchema'],
    },
  ).length;

  /// Every tool's definition together, without the instructions.
  int get toolsLength {
    var total = 0;
    for (final tool in tools) {
      total += toolLength(tool);
    }
    return total;
  }

  /// What the server carries on every request: [toolsLength] and the
  /// instructions.
  int get length => toolsLength + instructions.length;

  /// The largest tool, as `name length`.
  String get largest {
    Map<String, Object?>? best;
    for (final tool in tools) {
      if (best == null || toolLength(tool) > toolLength(best)) best = tool;
    }
    return best == null ? '-' : '${best['name']} ${toolLength(best)}';
  }

  /// One line for the measured table.
  String summary() =>
      '${server.padRight(10)} tools ${tools.length}  largest $largest  '
      'tools $toolsLength  instructions ${instructions.length}  total $length';
}

/// The ways [snapshots] pass their ceilings: [perTool] characters for any one
/// tool, [perServer] for one server with its instructions, [suite] for every
/// server together. Empty when they keep them.
List<String> suiteBudgetProblems(
  List<SuiteSnapshot> snapshots, {
  int perTool = kMcpToolDefinitionCeiling,
  int perServer = kMcpServerDefinitionCeiling,
  int suite = kMcpSuiteDefinitionCeiling,
}) {
  final problems = <String>[];
  var total = 0;
  for (final snapshot in snapshots) {
    for (final tool in snapshot.tools) {
      final length = SuiteSnapshot.toolLength(tool);
      if (length > perTool) {
        problems.add(
          '${snapshot.server}: tool `${tool['name']}` takes $length '
          'characters, past $perTool',
        );
      }
    }
    if (snapshot.length > perServer) {
      problems.add(
        '${snapshot.server} takes ${snapshot.length} characters with its '
        'instructions, past $perServer',
      );
    }
    total += snapshot.length;
  }
  if (total > suite) {
    problems.add('the suite takes $total characters, past $suite');
  }
  return problems;
}
