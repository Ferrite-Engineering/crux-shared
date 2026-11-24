// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Test helpers for a product's MCP server, kept out of the runtime barrel:
///
/// - `McpScriptedClient`: speaks to a server in process or to a server
///   binary, line by line;
/// - `McpTranscript`: the language-neutral conformance transcripts, replayed
///   through a client, with `mcpMatchPattern` their matcher;
/// - `expectDefinitionBudget`: fails when a server's definitions pass their
///   ceilings.
library;

export 'src/testing/budget_expectation.dart';
export 'src/testing/scripted_client.dart';
export 'src/testing/transcript.dart';
