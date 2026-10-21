# crux_yosys

Cross-suite Yosys subprocess infrastructure for the EDACrux suite.

The shape is deliberately narrow — this package owns the *runtime* of
shelling out to a Yosys binary and shaping the captured output. It owns
*nothing* product-specific:

- **`YosysRunner`** — spawns `yosys -q -p "<script>"`, captures
  stdout/stderr, writes JSON to a temp file, returns a sealed
  `YosysRunResult` (`YosysRunSuccess`, `YosysRunFailure`, `YosysRunTimeout`
  or `YosysRunCancelled`) and never throws. A failure's `kind`
  (`YosysFailureKind`) says why: `launch` is the executable that could not
  be started (not installed), distinct from `invalidRequest` and
  `outputUnreadable`, which share its synthetic exit code `-1`.
  `YosysRunRequest.frontend` (`YosysFrontend`) picks the read:
  `read_verilog`, `read_verilog -formal` for a formal elaboration, or one
  `read_slang -f <command file>` (yosys-slang, with `--single-unit`,
  `--top`, allow-listed `slangOptions`, and quoted paths in the command
  file; check `YosysAvailabilityService.probeSlang` first). yosys-slang
  writes `src` files relative to Yosys's working directory and async-reset
  flip-flops as `$aldff`, port connections as `$buf`: callers resolve and
  read them accordingly. VHDL is always lowered first by a standalone
  `ghdl --synth --out=verilog`, never the ghdl-yosys-plugin.
- **`YosysRunner.runScript`** — the same contract for a caller-written
  script (`YosysScriptRequest`, statements built with
  `YosysScriptCommands`), for a step the fixed script cannot express:
  reading a Liberty library before a gate-level design, say. `write_json` is
  appended; each statement must be one statement.
- **`YosysRunner.lowerVhdl`** — the VHDL lowering on its own, keeping the
  emitted Verilog at the caller's path (`VhdlLowerResult`, sealed, never
  thrown).
- **`YosysAvailabilityService`** — probes `yosys -V` and returns a
  structured `YosysAvailability` (`available` with version banner,
  `notFound`, or `unusable` with a structured reason code).
- **`YosysDiagnosticParser`** — parses Yosys's stderr into structured
  `YosysDiagnostic` value types (severity + message + optional
  `filePath:line:column`).
- **`ProcessRunner`** — minimal subprocess seam so tests can inject a
  fake. `DefaultProcessRunner` is the production implementation: it spawns
  via `Process.start` so it keeps a kill handle, drains stdout/stderr
  concurrently so a chatty child cannot wedge on a full pipe buffer, honours
  a `timeout` and a `cancelSignal`, and bounds retained output to a head and
  a tail so a verbose run cannot grow the parent heap without limit.
- **`ProcessRegistry`** — tracks live child processes so a host can kill
  orphans at shutdown. This package is pure Dart and cannot observe an
  application lifecycle itself, so the host drains the registry — in a
  Flutter app, `ProcessRegistry.instance.killAll()` on
  `AppLifecycleState.detached`. `DefaultProcessRunner` registers and
  unregisters automatically.

`ProcessRunner`, `ProcessRunResult`, `ProcessTermination` and
`ProcessRegistry` name no tool and depend on nothing else in this package.
They are the domain-neutral core, kept deliberately separable.
- **`YosysRunRequest` / `YosysRunResult` / `YosysAvailability` /
  `YosysDiagnostic` / `YosysUnavailableReason`** — immutable value
  types with `==`, `hashCode`, and `toString`.

The package is **pure Dart** with no Flutter dependency. The Riverpod
providers each consumer (one pre-release product today, another's check engine
next) wires up around this API stay in those products.

What deliberately does **not** live here:

- `YosysJsonParser` and the `NetlistModel` graph it produces — these are
  product-specific. Another consumer runs Yosys for syntax/elaboration checks
  and never wants a netlist.
- `ElaborationCacheService` — depends on the product's netlist model, stays there.
- All Riverpod providers — products compose this API into their own
  state-management surface.
- All ARB strings — exceptions carry structured machine-readable
  payloads (`YosysUnavailableReason`, severity enums, exit codes); each
  product's UI renders the localized text.

## Bundled-binary hook (future)

The runner and availability service today resolve the Yosys executable
via PATH search (and an explicit `executable` / `executableNameOverride`
parameter). A future iteration will accept a `YosysBinaryResolver`
abstraction so the suite can ship a bundled Yosys binary on platforms
where that's preferable to PATH discovery. The interface seam is named
but unimplemented in this release — bundling itself is a separate piece
of work.

## Status

Extracted from a single suite product once a second product needed the same
Yosys invocation, so that neither product had to depend on the other. The
four original concerns (runner, availability, diagnostic parser, value types)
were lifted verbatim; `YosysBinaryResolver` is the one added extension hook.
