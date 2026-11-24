// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

McpTool _tool(String name, int descriptionLength) => McpTool(
  name: name,
  description: 'd' * descriptionLength,
  fields: const <McpField>[],
);

/// The compact definition of a tool with no fields, around its name N and
/// description D: `{"name":"N","description":"D","inputSchema":{"type":
/// "object","properties":{},"required":[]}}`, counted by hand in six runs
/// of 9, 17, 16, 17, 16 and 15 characters: 90 plus the name and the
/// description.
int _length(String name, int descriptionLength) =>
    90 + name.length + descriptionLength;

void main() {
  test('a definition counts its compact JSON', () {
    expect(_tool('t', 10).definitionLength, _length('t', 10));
  });

  test('the server total adds the instructions', () {
    final server = fixtureServer(
      root: '.',
      tools: <McpTool>[_tool('a', 100), _tool('b', 200)],
    );
    expect(
      mcpServerDefinitionLength(server),
      _length('a', 100) + _length('b', 200) + fixtureInstructions.length,
    );
  });

  test('within budget passes; one past a ceiling fails', () {
    final atCeiling = _tool('t', 2000 - _length('t', 0));
    expect(atCeiling.definitionLength, 2000);
    expectDefinitionBudget(
      fixtureServer(root: '.', tools: <McpTool>[atCeiling]),
    );

    final over = _tool('t', 2001 - _length('t', 0));
    expect(
      () => expectDefinitionBudget(
        fixtureServer(root: '.', tools: <McpTool>[over]),
      ),
      throwsA(
        isA<McpBudgetExceeded>().having(
          (e) => e.toString(),
          'message',
          contains('tool `t` takes 2001 characters, past 2000'),
        ),
      ),
    );

    final crowded = fixtureServer(
      root: '.',
      tools: <McpTool>[_tool('a', 1500), _tool('b', 1500), _tool('c', 1000)],
    );
    final total = mcpServerDefinitionLength(crowded);
    const tail = 'characters with its instructions, past 4000';
    expect(mcpDefinitionBudgetProblems(crowded), <String>[
      'server `fixture` takes $total $tail',
    ]);
    expect(
      mcpDefinitionBudgetProblems(crowded, perServer: 10000),
      isEmpty,
    );
  });

  test('the fixture server is within the shipped ceilings', () {
    expectDefinitionBudget(fixtureServer(root: '.'));
  });
}
