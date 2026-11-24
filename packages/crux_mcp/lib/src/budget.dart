// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/src/server.dart';

/// The most characters one tool's definition may take.
const int kMcpToolDefinitionCeiling = 2000;

/// The most characters one server's definitions and `instructions` may take
/// together.
const int kMcpServerDefinitionCeiling = 4000;

/// The characters [server] carries on every request: each tool's definition
/// as compact JSON (`name`, `description`, `inputSchema`), plus its
/// `instructions` paragraph.
int mcpServerDefinitionLength(McpServer server) {
  var total = server.instructions.length;
  for (final tool in server.tools) {
    total += tool.definitionLength;
  }
  return total;
}

/// The ways [server]'s definitions pass their ceilings; empty when they keep
/// them.
List<String> mcpDefinitionBudgetProblems(
  McpServer server, {
  int perTool = kMcpToolDefinitionCeiling,
  int perServer = kMcpServerDefinitionCeiling,
}) {
  final problems = <String>[];
  for (final tool in server.tools) {
    final length = tool.definitionLength;
    if (length > perTool) {
      problems.add(
        'tool `${tool.name}` takes $length characters, past $perTool',
      );
    }
  }
  final total = mcpServerDefinitionLength(server);
  if (total > perServer) {
    problems.add(
      'server `${server.program.name}` takes $total characters with its '
      'instructions, past $perServer',
    );
  }
  return problems;
}
