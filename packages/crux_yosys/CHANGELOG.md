# Changelog

## Unreleased

### Added

- **`YosysRunner.runKeepingJson`: the `write_json` document as a file path,
  unread.** It takes `run`'s parameters; on success it returns a
  `YosysRunSuccess` whose new `jsonPath` names the document and whose
  `rawJson` is empty, so a consumer can stream a netlist of hundreds of
  megabytes (OpenTitan earlgrey flattened is 864 MB) instead of holding it as
  one string. The file is in the runner's temp directory under a name unique
  to the run, and **the caller must delete it**; the runner removes it only
  when the run does not succeed (non-zero exit, timeout, cancel, no or empty
  output, invalid request). The path is double-quoted in the `write_json`
  statement as before, so spaces and punctuation in the temp directory's path
  work (tested against a real Yosys); a path holding a double quote, `;` or a
  newline is still an `invalidRequest`. `run` and `runScript` are unchanged.
  A new method rather than a parameter on `run`, because a named parameter
  added to `run` makes every `extends YosysRunner` test double that overrides
  `run` an invalid override (SimCrux's `FakeYosysRunner` was one); the method
  adds nothing for such a double to implement. The runner, not the caller,
  chooses the path: it already owns collision-proof naming, and a
  caller-supplied path would need the validation and the cleanup rules twice.
  `YosysRunSuccess` gains an optional `jsonPath` rather than a new
  `YosysRunResult` subtype, which would break every consumer's exhaustive
  `switch`.

- **A child environment for `YosysRunner` and `YosysAvailabilityService`.**
  `YosysRunner` takes an optional `environment` (`Map<String, String>?`) in
  its constructor, and `run`, `runScript` and `lowerVhdl` take one per call.
  It is handed to every `ProcessRunner.run` the runner makes, the `ghdl`
  lowering spawn of a VHDL request included, so a GUI app can give the Yosys
  it starts the engine `PATH` it needs (an app opened from Finder has
  launchd's `PATH`) or a per-job `XDG_DATA_HOME`. A call's environment is
  laid over the constructor's variable by variable, so the call wins where
  both set one. `YosysAvailabilityService` takes the same constructor
  `environment` for `probe` and `probeSlang`. With none given, nothing is
  passed, as before. A class that extends `YosysRunner` and overrides `run`,
  `runScript` or `lowerVhdl` (a test fake, say) must add the `environment`
  parameter to its override, since Dart requires an override to accept every
  named parameter of the method it replaces.

- **`YosysFrontend` on `YosysRunRequest`: a formal read and the yosys-slang
  frontend.** `verilogFormal` reads with `read_verilog -formal` (`-formal
  -sv` for SystemVerilog), so `assert`, `assume`, `cover` and `$past` are
  read instead of refused; `slang` reads every source in one `read_slang`.
  The slang read is what OpenTitan earlgrey, Ibex and CVA6 were measured to
  need: `--single-unit` always (macros cross files), `--top <topModule>`
  when a top is set (modules the top never instantiates are not
  elaborated), the request's `slangOptions` from a fixed allow-list
  (`--ignore-initial`, `--ignore-assertions`, `--compat vcs`,
  `--blackboxed-module <id>`; anything else, or any option under another
  frontend, is an invalid request), and sources, `-I` and `-D` in a
  temporary `read_slang -f` command file with quoted paths, written in the
  runner's temp directory and removed with the run (paths with spaces work;
  a long file list stays out of argv). The default, `verilog`, is the
  script as before. The frontend survives VHDL lowering and
  include-directory linking (`YosysRunRequest.copyWith`).
- **`YosysAvailabilityService.probeSlang`**: whether this Yosys has
  `read_slang`, from `yosys -Q -T -p "help read_slang"`, cached per
  executable path. It reads the answer, not the exit status: Homebrew
  Yosys 0.69 prints "No such command" and exits 0.
- **`YosysRunner.runScript` and `YosysScriptCommands`: a caller-written
  script.** For steps the fixed elaboration cannot express, such as reading
  a Liberty library before a gate-level design: the statements run in
  order, `write_json` is appended, and the result is the same
  `YosysRunResult` with the same never-throws, kill and cleanup behaviour.
  Each statement must be one statement (no `;` or newline, quotes paired);
  `readLiberty`, `readVerilog`, `readSlangCommandFile` (with
  `slangCommandFile` for its contents) and `hierarchy` build them with the
  fixed script's quoting and checks.
- **`YosysRunner.lowerVhdl`: the VHDL lowering on its own.** Runs the same
  standalone `ghdl --synth --out=verilog` and keeps the emitted Verilog at
  a path the caller chose, for a tool that needs the Verilog itself (an
  equivalence check's gold design). Never throws; `VhdlLowerResult` is
  sealed. `run` now lowers through it, so the two cannot drift.

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
