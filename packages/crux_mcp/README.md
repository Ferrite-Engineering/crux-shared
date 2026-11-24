# crux_mcp

The shared core of the suite's Model Context Protocol servers. Each product
serves its tools with `<product> mcp [--root <dir>] [--license-file <path>]`,
a subcommand of its headless binary; this package is everything those servers
must do the same way, so they keep one protocol. Pure Dart, permanently: no
Flutter anywhere in the dependency closure (`test/no_flutter_dependency_test.dart`).

## What it holds

| Part | What |
|---|---|
| Transport | `McpServer.serve`: newline-delimited JSON-RPC 2.0 on stdin and stdout, one message per line. `initialize` (answers the client's revision when it is one of `kMcpProtocolVersions`, else the newest; capabilities `tools`; `serverInfo`; the `instructions` paragraph, at most 600 characters), `ping`, `tools/list`, `tools/call`. A line past 4 MiB, its newline included, is `-32600` with an `id` of null; a line that is not JSON is `-32700`; an unknown method is `-32601`; an unknown tool or a `tools/call` with no name is `-32602`. Notifications are accepted and not answered; `notifications/cancelled` stops a call that has not started and drops the answer of one that has. A call that sends a progress token gets `notifications/progress` when its runner reports. A runner's `print` goes to stderr: stdout carries only the protocol. |
| Tool registry | `McpTool` and `McpField`: a name, a description, typed fields (text, path, integer, boolean, time; one or many), the required list, and the flag each field becomes. One table makes both the `inputSchema` and the argument vector, so they cannot disagree. `McpTool.check` refuses an unknown field, a wrong type, a missing required field and a path outside the root, in that order, and the server answers with a `usage_error` document and runs nothing. |
| The document | `McpDocument`: the eight members (`schema_version`, `tool`, `command`, `outcome`, `engines`, `design`, `body`, `diagnostics`), always present, in that order, null when empty, written by `mcpRenderJson` (two-space indent, a fixed escape set) and one newline. The `--json` door and the server use the same writer. `McpOutcome`'s six outcomes, `McpDiagnostic`, and `McpExitCodes`, the table each product supplies (only `completed` exits 0; `McpExitCodes.suite` is the convention for new subcommands). |
| Results | `McpCommandOutput`: `content[0]` is the command's text unchanged, and `isError` is true for every outcome that is not an answer and for any text that is not a document. |
| Locations and links | `McpLocation`'s five forms (source; a signal at a time, with its link; a place in a dump; a cell or net of a design; a test), each written with every member present, and read back with the link checked. `waveCruxLink` and `netCruxLink` percent-encode every UTF-8 byte except `A-Z a-z 0-9 - . _ ~` as upper-case `%XX`, and refuse what the receiving app's link reader refuses. The reference server's vectors are a test that must match byte for byte. |
| Confinement | `Confinement(root)`: `crux_cxp`'s `CxpPathContainment` with the root as its one directory, keyed by `crux_io`'s `containmentKey`. No containment logic of its own. Network and device spellings are refused on their text on every host; `confineAll` checks the files a project, filelist or manifest names. The path returned is the absolute text that was checked. |
| Tier gate | `McpTierGate`: `requireTier` and `refuse` give `licence_error` with `licence.tier_required` and the fix (the three places a licence is read from); `withhold` gives the `licence.withheld` warning. The tier answer is the product's headless resolver's. |
| Telemetry | `McpTelemetry`: one `mcp.tool_call` event per call of a served tool, with `tool`, `outcome` and a `duration` bucket, and nothing else. The product supplies consent (asked per call) and the sink into its telemetry service; nothing is sent when `CI` is set. |
| Budget | `mcpDefinitionBudgetProblems`, and `expectDefinitionBudget` in `crux_mcp_testing.dart`: 2,000 characters per tool definition, 4,000 per server with its `instructions`. |
| Conformance | `crux_mcp_testing.dart`: `McpScriptedClient` (in process or over a binary's stdio) and `McpTranscript`, which replays the JSON transcripts in `test/conformance/transcripts/`. The format is documented on `McpTranscript`; it is language neutral, so a server written in another language is held to the same files. `test/conformance/reference_live_test.dart` replays them against the binary named by `CRUX_MCP_SERVER_BIN` (arguments before `--root` in `CRUX_MCP_SERVER_ARGS`, default `mcp`); it declares no test when the variable is unset, so CI never runs it. |

## Why the protocol is written here, not taken from a package

`dart_mcp` (0.5.2, BSD-3-Clause, Dart SDK `^3.7.0`) would pass the
supply-chain licence gate and builds on the pinned SDK. It is not used, for
three reasons. Its protocol revisions run to `2025-11-25`, and every suite
server must answer the same revisions. It frames messages through
`json_rpc_2` and `stream_channel` with no line limit, and answers an unknown
tool with an error result rather than `-32602`, where the suite's servers
must answer the 4 MiB limit, `-32602` and a `usage_error` document
identically. And it is a 0.x API. The
subset the servers need (four methods and one notification) is a few hundred
lines with nothing to track upstream.

## Exported on purpose

Every symbol here is exported for the four products' servers and their
`--json` commands, which adopt it after this package lands; until then
`tool/unused-exports.py` counts them as unused.
