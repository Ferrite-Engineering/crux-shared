// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/src/budget.dart';
import 'package:crux_mcp/src/server.dart';

/// Thrown by [expectDefinitionBudget] when a ceiling is passed.
class McpBudgetExceeded implements Exception {
  /// An exception listing [problems].
  const McpBudgetExceeded(this.problems);

  /// Each ceiling passed, and by what.
  final List<String> problems;

  @override
  String toString() =>
      'McpBudgetExceeded: the definitions pass their budget:\n'
      '${problems.join('\n')}';
}

/// Fails a product's test when [server]'s definitions pass their budget:
/// [perTool] characters for any one tool, [perServer] for every tool and the
/// `instructions` together. Throws [McpBudgetExceeded], which any test
/// framework reports as a failure.
void expectDefinitionBudget(
  McpServer server, {
  int perTool = kMcpToolDefinitionCeiling,
  int perServer = kMcpServerDefinitionCeiling,
}) {
  final problems = mcpDefinitionBudgetProblems(
    server,
    perTool: perTool,
    perServer: perServer,
  );
  if (problems.isNotEmpty) throw McpBudgetExceeded(problems);
}
