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
