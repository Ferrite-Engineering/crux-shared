# Changelog

## Unreleased

- `McpTelemetry.desktop(HeadlessTelemetry)`: tool-call counting under the
  consent the product's desktop app recorded, from `crux_telemetry_core`
  (re-exported with `CruxTelemetryProduct` and `TelemetryPolicy`).
  `McpTelemetry.close`, awaited by `McpServer.serve` once its input has
  ended, sends what is held.

## 0.1.0

- First version: the stdio transport, the tool registry and argument
  checking, the eight-member document with its outcomes, diagnostics and
  exit-code tables, the five location forms and the WaveCrux and NetCrux
  link builders, path confinement over `crux_cxp`'s containment rule, the
  licence-gate wording, the `mcp.tool_call` telemetry event, the definition
  budget check, and the conformance transcripts with a scripted client.
