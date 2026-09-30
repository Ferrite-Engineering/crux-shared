# Changelog

## Unreleased

### Security

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
