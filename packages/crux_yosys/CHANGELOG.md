# Changelog

## Unreleased

### Added

- **`YosysRunRequest.allowUndefinedModules`** (default `false`). When set, the
  runner emits `hierarchy` without `-check`, so a design that instantiates a
  module no source defines elaborates instead of failing with "is not part of
  the design". Yosys keeps each such instance as a cell of the undefined type,
  with its connections (positional ones named `$1`, `$2`, ...) and no
  `port_directions`, and writes no module entry for the type. The flag is part
  of the request's equality and hash, and it is carried through the VHDL
  lowering step. Requests that leave it unset produce the same script as
  before.

### Fixed

- **`DefaultProcessRunner` starts an OSS CAD Suite Yosys with the suite's own
  `bin` and `lib` first on its `PATH`** (Windows), through
  `ossCadSuiteSpawnEnvironment`. Yosys from the suite failed the availability
  probe as `exec_failed` whenever an earlier `PATH` entry shipped a DLL of the
  same name.

### Security

- **`extraCommands` entries must each be one statement.** They were joined
  into the `-p` script as written, the one interpolated input the runner's
  quote-and-separator check never saw, so an entry like `proc; exec -- id`
  ran a second statement. An entry containing `;`, a newline or `"` is now an
  `ArgumentError` from `buildScript`, which `run` returns as a
  `YosysRunFailure` of kind `invalidRequest`. Which passes are acceptable
  stays the consumer's policy: `exec` and `shell` are single statements too.
- **`DefaultProcessRunner` resolves a bare executable name to an absolute
  path before it spawns.** On Windows, `CreateProcess` searches the launching
  process's current directory before `PATH`, and a product launched from a
  terminal inside a repository has that repository as its current directory,
  so a `yosys.exe` or `ghdl.exe` committed there would have run in place of
  the installed one. The name is resolved with `crux_io`'s strict
  `SpawnHost.requireExecutable` against the `PATH` the child is given, so a
  binary found only through an augmented `PATH` resolves too. **An engine that
  is not installed starts nothing**: rather than a bare name that Windows
  would look for in the launch directory, `run` throws the `ProcessException`
  (`not found on PATH`) a missing binary always produced, so `YosysRunner`
  still reports a launch failure and `YosysAvailabilityService` still reports
  not found. The identity off Windows. `crux_io` is a new dependency.
- **`DefaultProcessRunner` takes an optional `spawnHost`** (default
  `SpawnHost.current()`), so the Windows resolution is tested on any machine.
  Existing constructions are unchanged.

### Fixed

- **`DefaultProcessRunner` no longer returns partial output as if it were
  complete.** When the drain grace after a process's exit ran out, `run`
  returned whatever stdout/stderr it had captured by then, with nothing to
  say the tool's last lines were missing. That is the class of bug that
  produced a false clean in another product's lint engines, where the one
  stderr line a tool printed arrived after its exit. The grace stays, and
  stays bounded, because a killed wrapper script leaves a grandchild holding
  the pipe and an unbounded wait would hang a run after its timeout had
  fired; what changes is what its expiry means. After a timeout or a cancel
  the result is returned under its termination reason, as before. After a
  process that exited on its own, a pipe still open or a read that failed
  now throws `crux_io`'s `ProcessOutputIncompleteException`, and
  `YosysRunner` maps it to a `YosysRunFailure` of kind `outputUnreadable`
  (whose doc now covers the log as well as the `write_json` file), and
  `YosysAvailabilityService` to `execFailed`, so neither throws. A pipe read
  error on an exited process was previously swallowed. The wait itself is
  the shared `drainProcessOutput`, the same code every subprocess read in
  the suite goes through. `defaultDrainGrace` stays at 2 s, shorter than
  `crux_io`'s 5 s, because its cost lands on every cancel.
- **Include paths and defines reach Yosys again** (crux-shared#23). The
  script quoted every `read_verilog -I` and `-D` value, and Yosys keeps the
  quotes inside an option value (it strips them only from file names), so no
  include directory was ever found and no define ever applied. Both are now
  emitted bare. An include directory whose path contains whitespace, which
  Yosys cannot take as `-I`, is reached through a link in a per-run temp
  directory (a symlink, or a junction on Windows) that `run` removes
  afterwards. A define containing whitespace cannot be expressed in a Yosys
  script and comes back as a `YosysFailureKind.invalidRequest` failure.
- The `hierarchy -top <module>` and `ghdl -e <unit>` names are now emitted
  bare (unquoted) again. The earlier space-safety change quoted them, but
  Yosys treats surrounding quotes as part of the module name (`-top "and2"`
  looks for a module literally named `"and2"` and errors), which broke
  elaboration for any design with an explicit top module and every VHDL
  design. Module/unit names are validated as bare HDL identifiers (refused
  loudly if they contain whitespace or metacharacters); paths and defines
  remain double-quoted.

- `YosysRunner.run` now honours its documented never-throws contract. A
  missing Yosys binary (`ProcessException`), a source path containing a
  double quote (`ArgumentError`), and an unreadable `write_json` temp file
  now come back as a `YosysRunFailure` with the new
  `YosysRunner.launchFailureExitCode` instead of escaping into the caller's
  async context.
- `DefaultProcessRunner` no longer hangs after killing a process whose
  grandchildren inherited its pipes. The post-exit drain is bounded by the
  new `drainGrace`, so a `timeout` is now genuinely an upper bound on `run`.
- `YosysAvailabilityService.probe` now bounds its subprocess with
  `probeTimeout` (default 10 s) and reports
  `YosysUnavailableReason.probeTimedOut`, rather than hanging forever on a
  binary that never responds.
- `DefaultProcessRunner` no longer retains unbounded subprocess output. Both
  streams are still drained in full, but only `outputHeadLimit` +
  `outputTailLimit` characters are kept; `ProcessRunResult.stdoutTruncated` /
  `stderrTruncated` report when that happened.
- An errored `cancelSignal` no longer becomes an unhandled async error.
- `write_json` temp file names now include the pid and a random suffix, so
  two products elaborating concurrently cannot collide and delete each
  other's output.

### Added

- `YosysRunFailure.kind` and `YosysFailureKind` — `launch`, `invalidRequest`,
  `outputUnreadable`, `nonZeroExit`, `noOutput` — say *why* a run failed.
  `YosysRunner.launchFailureExitCode` (`-1`) is shared by three failures in
  which no process status exists, and only `launch` means the executable
  (Yosys, or `ghdl` for a VHDL request) could not be started; a caller
  previously had to combine that exit code with the wording of `stderr` to
  tell them apart. Every failure the runner returns now carries its kind.
  Backward compatible: the exit codes are unchanged (still `-1` for all
  three), the constructor parameter is optional, and a failure built without
  one derives its kind from the exit code (`-1` → `launch`, `0` →
  `noOutput`, anything else → `nonZeroExit`). The discriminator is a field
  rather than a new subtype, so existing exhaustive switches over
  `YosysRunResult` still compile.
- `ProcessRegistry` — tracks live child processes so a host can terminate
  orphans at shutdown (`ProcessRegistry.instance.killAll()` on
  `AppLifecycleState.detached`). `DefaultProcessRunner` registers and
  unregisters automatically.

## 0.0.1

- Initial extraction. `YosysRunner`, `YosysAvailabilityService`,
  `YosysDiagnosticParser`, `ProcessRunner` / `DefaultProcessRunner`,
  and the supporting value types (`YosysRunRequest`, `YosysRunResult`,
  `YosysAvailability`, `YosysDiagnostic`, `YosysUnavailableReason`,
  `ProcessRunResult`) lifted verbatim from a pre-release suite product's
  open-core Yosys service layer.
  Riverpod providers, `YosysJsonParser`, `NetlistModel`, and
  `ElaborationCacheService` stay in that product. `YosysBinaryResolver`
  extension hook reserved for a future bundled-binary implementation.
