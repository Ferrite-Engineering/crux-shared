// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/crux_mcp.dart';

/// The program every fixture server names.
const McpProgram fixtureProgram = McpProgram(name: 'fixture', version: '0.0.1');

/// A short instructions paragraph.
const String fixtureInstructions =
    'Call fixture tools to read the fixture files. Cite every result with '
    'its link.';

/// Two tools covering every field kind.
final List<McpTool> fixtureTools = <McpTool>[
  McpTool(
    name: 'inspect',
    description: 'Inspect one file.',
    fields: const <McpField>[
      McpField('file', kind: McpFieldKind.path),
      McpField(
        'depth',
        kind: McpFieldKind.integer,
        flag: '--depth',
        minimum: 1,
      ),
      McpField('verbose', kind: McpFieldKind.boolean, flag: '--verbose'),
      McpField(
        'at',
        kind: McpFieldKind.time,
        flag: '--at',
        description: 'A tick, or a time such as 1500ns.',
      ),
      McpField(
        'names',
        kind: McpFieldKind.text,
        flag: '--name',
        many: true,
      ),
      McpField('mode', kind: McpFieldKind.text, flag: '--mode'),
    ],
    required: const <String>['file'],
  ),
  McpTool(
    name: 'scan',
    description: 'Scan files.',
    fields: const <McpField>[
      McpField('paths', kind: McpFieldKind.path, many: true),
      McpField('include', kind: McpFieldKind.path, flag: '-I', many: true),
    ],
  ),
];

/// A runner that answers `completed` with the argument vector as its body,
/// and records every call it is given in [calls].
McpCommandRunner recordingRunner(List<McpCall> calls) => (call) async {
  calls.add(call);
  return McpCommandOutput.document(
    McpDocument(
      tool: fixtureProgram,
      command: call.tool.command,
      outcome: McpOutcome.completed,
      body: <String, Object?>{'argv': call.arguments.argv},
    ),
  );
};

/// A fixture server over [root].
McpServer fixtureServer({
  required String root,
  McpCommandRunner? runner,
  List<McpCall>? calls,
  Confinement? confinement,
  McpTelemetry? telemetry,
  void Function(String line)? log,
  List<McpTool>? tools,
}) => McpServer(
  program: fixtureProgram,
  instructions: fixtureInstructions,
  tools: tools ?? fixtureTools,
  confinement: confinement ?? Confinement(root),
  runner: runner ?? recordingRunner(calls ?? <McpCall>[]),
  telemetry: telemetry,
  log: log ?? (_) {},
);
