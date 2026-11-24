// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The shared core of the suite's Model Context Protocol servers, so every
/// product's `<product> mcp` keeps one protocol.
///
/// - `McpServer`: newline-delimited JSON-RPC 2.0 on stdio, the methods
///   `initialize`, `ping`, `tools/list` and `tools/call`, cancellation and
///   progress, a 4 MiB line limit, the protocol revisions in
///   `kMcpProtocolVersions`.
/// - `McpTool` and `McpField`: a tool's typed fields make both its
///   `inputSchema` and the command line it runs; a bad argument is a
///   `usage_error` document and nothing runs.
/// - `McpDocument`: the eight-member document every `--json` command writes
///   and every tool returns, its six `McpOutcome`s, `McpDiagnostic`s, and
///   the `McpExitCodes` table each product supplies.
/// - `McpLocation`: the five location forms, and the `waveCruxLink` and
///   `netCruxLink` builders with their percent-encoding.
/// - `Confinement`: every path inside one root, on `crux_cxp`'s
///   containment rule.
/// - `McpTierGate`: the words a closed licence gate says.
/// - `McpTelemetry`: the one `mcp.tool_call` event, under the product's
///   consent.
///
/// Test helpers (the scripted client, the conformance transcripts and the
/// definition budget check) are in `crux_mcp_testing.dart`.
library;

export 'src/budget.dart';
export 'src/confinement.dart';
export 'src/document.dart';
export 'src/json_writer.dart';
export 'src/location.dart';
export 'src/outcome.dart';
export 'src/protocol.dart';
export 'src/result.dart';
export 'src/server.dart';
export 'src/telemetry.dart';
export 'src/tier_gate.dart';
export 'src/tool.dart';
