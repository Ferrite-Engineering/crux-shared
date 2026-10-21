// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Source-language hint attached to one [YosysSourceFile]. Drives how the
/// file is brought into Yosys: `read_verilog` for Verilog / SystemVerilog;
/// VHDL is pre-synthesized to Verilog by a standalone `ghdl --synth`
/// invocation and the emitted Verilog is then `read_verilog`'d like any
/// other Verilog source (no Yosys GHDL plugin is loaded).
enum YosysSourceLanguage {
  /// IEEE 1364 Verilog. Read with `read_verilog`.
  verilog,

  /// IEEE 1800 SystemVerilog. Read with `read_verilog -sv`.
  systemVerilog,

  /// IEEE 1076 VHDL. Lowered to Verilog out-of-band via
  /// `ghdl --synth --out=verilog … -e <top>`, then read with
  /// `read_verilog`.
  vhdl,
}

/// Which Yosys frontend reads a request's Verilog and SystemVerilog sources.
///
/// VHDL is unaffected: it is always lowered by `ghdl --synth` first and the
/// emitted Verilog is read by the frontend chosen here.
enum YosysFrontend {
  /// The built-in frontend, `read_verilog` (`-sv` for SystemVerilog files).
  verilog,

  /// The built-in frontend with formal constructs enabled,
  /// `read_verilog -formal` (`-formal -sv` for SystemVerilog files):
  /// immediate and concurrent `assert`, `assume` and `cover`, `$past` and
  /// the other formal-only system functions are read instead of refused.
  verilogFormal,

  /// The yosys-slang frontend, `read_slang`, which reads every Verilog and
  /// SystemVerilog source as SystemVerilog in one compilation unit.
  ///
  /// Needs a Yosys with yosys-slang (the OSS CAD Suite build has it built
  /// in; Homebrew's does not): ask `YosysAvailabilityService.probeSlang`
  /// first. Without it the run fails with Yosys's own "No such command".
  ///
  /// What the runner passes, and why (measured on OpenTitan earlgrey, Ibex
  /// and CVA6):
  ///
  /// - `--single-unit` always: macros then cross files, as they do in one
  ///   `read_verilog`; without it every `` `ASSERT `` after its defining
  ///   file is undefined.
  /// - `--top <topModule>` whenever a top is set: otherwise slang elaborates
  ///   every module in the file list, including ones the top never
  ///   instantiates.
  /// - The request's allow-listed [YosysRunRequest.slangOptions].
  /// - Sources, `-I` and `-D` through a temporary command file
  ///   (`read_slang -f`) in the runner's temp directory, removed with the
  ///   run: paths there are quoted, so a path with spaces works (a quoted
  ///   name on `read_slang`'s own command line keeps its quotes), and a
  ///   list of hundreds of files stays out of the process argument limit.
  ///   The temp directory's own path must not contain white space.
  ///
  /// What a caller must know about the result: yosys-slang writes each `src`
  /// file **relative to Yosys's working directory** (`../../rtl/x.sv`), with
  /// or without `--diag-abs-paths`, so resolve span files against the
  /// directory Yosys ran in (this process's, for the runner) before
  /// relating them to the project; and it writes an asynchronously reset
  /// flip-flop as `$aldff` and a port connection as a `$buf` cell, where the
  /// built-in reader writes `$adff` and a plain wire.
  slang,
}

/// One source-language input to a [YosysRunRequest]. Carries an
/// absolute path plus the language hint that drives Yosys's read
/// command selection.
@immutable
class YosysSourceFile {
  /// Creates a source file. Default language is [YosysSourceLanguage.verilog]
  /// so callers that pass a plain path get Verilog without restating it.
  const YosysSourceFile(
    this.path, {
    this.language = YosysSourceLanguage.verilog,
  });

  /// Convenience constructor for a VHDL source file.
  const YosysSourceFile.vhdl(String path)
    : this(path, language: YosysSourceLanguage.vhdl);

  /// Convenience constructor for a SystemVerilog source file.
  const YosysSourceFile.systemVerilog(String path)
    : this(path, language: YosysSourceLanguage.systemVerilog);

  /// Absolute path to the source file.
  final String path;

  /// Per-file language. Selects the Yosys read command at script-build
  /// time; see [YosysSourceLanguage].
  final YosysSourceLanguage language;

  @override
  bool operator ==(Object other) =>
      other is YosysSourceFile &&
      other.path == path &&
      other.language == language;

  @override
  int get hashCode => Object.hash(path, language);

  @override
  String toString() => 'YosysSourceFile($path, $language)';
}

/// Inputs to one Yosys elaboration: source files, optional top module,
/// preprocessor defines, include paths, and free-form extra commands.
@immutable
class YosysRunRequest {
  /// Creates a request from a list of typed [YosysSourceFile]s.
  ///
  /// For designs that contain VHDL the runner first lowers the VHDL to
  /// Verilog with a standalone `ghdl --synth --out=verilog` invocation
  /// elaborating [vhdlTopUnit], then reads the emitted Verilog together
  /// with any original Verilog sources under a single `read_verilog`
  /// pass so `hierarchy` binds instances by module name. See [topModule]
  /// / [vhdlTopUnit] for how the top-of-design is selected.
  const YosysRunRequest({
    required this.sources,
    this.topModule,
    this.defines = const <String>[],
    this.includePaths = const <String>[],
    this.extraCommands = const <String>[],
    this.vhdlStandard,
    this.vhdlTopUnit,
    this.frontend = YosysFrontend.verilog,
    this.slangOptions = const <String>[],
  });

  /// Convenience constructor that takes a list of Verilog file paths.
  /// Equivalent to mapping each path to
  /// `YosysSourceFile(path, language: verilog)`, for callers that don't
  /// need per-file language hints.
  factory YosysRunRequest.fromPaths({
    required List<String> sourceFiles,
    String? topModule,
    List<String> defines = const <String>[],
    List<String> includePaths = const <String>[],
    List<String> extraCommands = const <String>[],
  }) {
    return YosysRunRequest(
      sources: <YosysSourceFile>[
        for (final path in sourceFiles) YosysSourceFile(path),
      ],
      topModule: topModule,
      defines: defines,
      includePaths: includePaths,
      extraCommands: extraCommands,
    );
  }

  /// Typed source files. Order matters because some tools resolve
  /// `include` files relative to declaration order; the runner emits
  /// Verilog read commands in the order they appear in this list, then
  /// the VHDL block.
  final List<YosysSourceFile> sources;

  /// Optional top-module name passed to `hierarchy -top`. When `null`,
  /// Yosys uses its own heuristic ("the module that nothing else
  /// instantiates"). For pure-VHDL designs the runner additionally
  /// passes [vhdlTopUnit] to `ghdl <top>`; when absent, [topModule] is
  /// used.
  final String? topModule;

  /// `-D NAME[=VALUE]` defines passed to the Verilog preprocessor.
  final List<String> defines;

  /// `-I path` include search directories.
  final List<String> includePaths;

  /// Additional Yosys script commands inserted between `proc` and
  /// `write_json`. Used by integration tests and Pro overlays that need
  /// custom passes.
  final List<String> extraCommands;

  /// VHDL standard passed to `ghdl --synth` as `--std=<value>` when the
  /// request contains any VHDL source (e.g. `'08'` for VHDL-2008, `'93'`
  /// for VHDL-93). When null no `--std` flag is emitted and GHDL uses its
  /// own default, matching the behavior of the previous plugin pipeline.
  final String? vhdlStandard;

  /// Top design unit passed to `ghdl --synth … -e <top>` when the request
  /// contains any VHDL source. Falls back to [topModule] when null, then
  /// to `top` as the last-resort default.
  final String? vhdlTopUnit;

  /// The frontend that reads the Verilog and SystemVerilog sources; the
  /// built-in `read_verilog` unless a formal or yosys-slang read is asked
  /// for.
  final YosysFrontend frontend;

  /// The caller's own `read_slang` options, for [YosysFrontend.slang] only
  /// (a request with any under another frontend is refused). Each entry is
  /// one option from a fixed allow-list (`YosysScriptCommands.slangOptions`
  /// says which): `--ignore-initial`, `--ignore-assertions`,
  /// `--compat vcs`, or `--blackboxed-module <identifier>`. A lint pass that
  /// reads no assertion passes the first two; a formal read passes neither.
  /// Anything else is an invalid request.
  final List<String> slangOptions;

  /// A copy with [includePaths] replaced; every other field, [frontend]
  /// included, is carried over.
  YosysRunRequest copyWith({List<String>? includePaths}) => YosysRunRequest(
    sources: sources,
    topModule: topModule,
    defines: defines,
    includePaths: includePaths ?? this.includePaths,
    extraCommands: extraCommands,
    vhdlStandard: vhdlStandard,
    vhdlTopUnit: vhdlTopUnit,
    frontend: frontend,
    slangOptions: slangOptions,
  );

  /// Returns true if any source in [sources] is VHDL.
  bool get hasVhdlSources =>
      sources.any((s) => s.language == YosysSourceLanguage.vhdl);

  /// Returns true if any source in [sources] is Verilog or
  /// SystemVerilog.
  bool get hasVerilogSources => sources.any(
    (s) =>
        s.language == YosysSourceLanguage.verilog ||
        s.language == YosysSourceLanguage.systemVerilog,
  );

  /// Plain-path view of the sources, in declaration order. Convenience
  /// for callers that need to log or hash the request without caring
  /// about per-file language.
  List<String> get sourcePaths => <String>[for (final s in sources) s.path];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! YosysRunRequest) return false;
    if (other.topModule != topModule) return false;
    if (other.vhdlStandard != vhdlStandard) return false;
    if (other.vhdlTopUnit != vhdlTopUnit) return false;
    if (other.frontend != frontend) return false;
    if (!_listEq(other.sources, sources)) return false;
    if (!_listEq(other.defines, defines)) return false;
    if (!_listEq(other.includePaths, includePaths)) return false;
    if (!_listEq(other.extraCommands, extraCommands)) return false;
    if (!_listEq(other.slangOptions, slangOptions)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    topModule,
    vhdlStandard,
    vhdlTopUnit,
    frontend,
    Object.hashAll(sources),
    Object.hashAll(defines),
    Object.hashAll(includePaths),
    Object.hashAll(extraCommands),
    Object.hashAll(slangOptions),
  );
}

/// Outcome of a [YosysRunRequest]. Sealed so widget code can pattern-match
/// without forgetting a case.
@immutable
sealed class YosysRunResult {
  const YosysRunResult({
    required this.stdout,
    required this.stderr,
  });

  /// Captured stdout from the yosys subprocess.
  final String stdout;

  /// Captured stderr from the yosys subprocess.
  final String stderr;
}

/// Yosys exited cleanly and produced a `write_json` document.
@immutable
final class YosysRunSuccess extends YosysRunResult {
  /// Creates a success result.
  const YosysRunSuccess({
    required this.rawJson,
    required super.stdout,
    required super.stderr,
  });

  /// UTF-8 contents of the `write_json` output file.
  final String rawJson;
}

/// Why a [YosysRunFailure] happened.
///
/// The exit code alone cannot say: `YosysRunner.launchFailureExitCode` (`-1`)
/// is shared by three failures in which no real exit status exists, and only
/// one of them means "the tool is not installed". Branch on this instead.
enum YosysFailureKind {
  /// The executable could not be started — Yosys, or `ghdl` for a request
  /// with VHDL sources, is missing, not on `PATH`, or not executable. Nothing
  /// ran. Reported with `YosysRunner.launchFailureExitCode`;
  /// [YosysRunResult.stderr] names the executable that failed to spawn.
  launch,

  /// The request could not be turned into a valid command: a path or define
  /// containing a double quote, semicolon or newline, a top-module or VHDL
  /// unit name that is not a bare identifier, or a malformed VHDL standard.
  /// Nothing ran. Reported with `YosysRunner.launchFailureExitCode`.
  invalidRequest,

  /// The tool ran and exited on its own, but its output could not be read:
  /// the `write_json` file could not be read back (removed underneath the
  /// runner, unreadable, or not UTF-8), or its stdout/stderr did not reach
  /// end-of-file after the exit, so the log may be missing the last
  /// diagnostic it printed. Reported with `YosysRunner.launchFailureExitCode`;
  /// [YosysRunResult.stderr] says which.
  outputUnreadable,

  /// Yosys, or the `ghdl --synth` pre-step, exited with a non-zero status.
  /// [YosysRunFailure.exitCode] is that status and [YosysRunResult.stderr]
  /// carries the tool's diagnostics.
  nonZeroExit,

  /// The tool exited `0` but produced nothing to use: no `write_json` file, an
  /// empty one, or no Verilog from `ghdl --synth`. [YosysRunFailure.exitCode]
  /// is `0`.
  noOutput,
}

/// The runner's synthetic exit code for a failure with no real exit status.
/// Mirrors `YosysRunner.launchFailureExitCode`, which a test pins to it; kept
/// here so this library does not import the runner.
const int _launchFailureExitCode = -1;

/// Yosys (or its `ghdl --synth` pre-step) did not produce a usable
/// `write_json` document. [kind] says why; callers should typically inspect
/// [stderr] with the diagnostic parser before surfacing the failure.
@immutable
final class YosysRunFailure extends YosysRunResult {
  /// Creates a failure result.
  ///
  /// [kind] is optional so a failure built without one — a test double, or a
  /// caller written before the field existed — still means what its exit code
  /// meant: see [kind].
  const YosysRunFailure({
    required this.exitCode,
    required super.stdout,
    required super.stderr,
    YosysFailureKind? kind,
    // Not `this._kind`: a private initializing formal is published under its
    // private name in tooling that reads parameter names, including the
    // api/*.api.txt goldens, and callers pass `kind:`.
    // ignore: prefer_initializing_formals
  }) : _kind = kind;

  /// The process exit code, or `YosysRunner.launchFailureExitCode` (`-1`) when
  /// no process status exists ([YosysFailureKind.launch],
  /// [YosysFailureKind.invalidRequest], [YosysFailureKind.outputUnreadable]).
  /// Zero means the tool exited cleanly but produced nothing
  /// ([YosysFailureKind.noOutput]).
  final int exitCode;

  final YosysFailureKind? _kind;

  /// Why the run failed.
  ///
  /// Every failure `YosysRunner` returns carries its kind explicitly. A
  /// failure constructed without one derives it from [exitCode]: `-1` reads as
  /// [YosysFailureKind.launch] (what such a failure almost always stood for
  /// before this field existed), `0` as [YosysFailureKind.noOutput], and any
  /// other value as [YosysFailureKind.nonZeroExit].
  YosysFailureKind get kind =>
      _kind ??
      switch (exitCode) {
        _launchFailureExitCode => YosysFailureKind.launch,
        0 => YosysFailureKind.noOutput,
        _ => YosysFailureKind.nonZeroExit,
      };
}

/// The Yosys subprocess exceeded its time [budget] and was killed.
///
/// Distinct from [YosysRunFailure] so the elaboration pipeline can surface a
/// dedicated "timed out" diagnostic rather than a generic non-zero-exit
/// message. Any partial `write_json` temp file is cleaned up by the runner
/// before this result is returned.
@immutable
final class YosysRunTimeout extends YosysRunResult {
  /// Creates a timeout result.
  const YosysRunTimeout({
    required this.budget,
    required super.stdout,
    required super.stderr,
  });

  /// The elapsed budget after which the runner killed the process.
  final Duration budget;
}

/// The Yosys subprocess was killed because the caller's `cancelSignal`
/// fired — a tab close, or a re-elaboration that supersedes this one.
///
/// Not an error: the elaboration pipeline drops the now-stale result rather
/// than surfacing a failure toast for work the user themselves invalidated.
@immutable
final class YosysRunCancelled extends YosysRunResult {
  /// Creates a cancelled result.
  const YosysRunCancelled({
    required super.stdout,
    required super.stderr,
  });
}

/// A Yosys script the caller writes, for the steps the fixed elaboration
/// script cannot express: reading a Liberty library before the design, a
/// gate-level read with no `proc`, a pass sequence of the caller's own.
///
/// Run by `YosysRunner.runScript`, which appends one `write_json` to a temp
/// file and returns the document as [YosysRunSuccess.rawJson], exactly as
/// `YosysRunner.run` does. Build file-reading statements with
/// `YosysScriptCommands` so paths are quoted and checked the way the fixed
/// script's are.
///
/// Each entry of [commands] must be a single statement: no `;`, newline or
/// double quote outside the quoting `YosysScriptCommands` emits. A consumer
/// that takes statements from a project file still filters them against its
/// own allow-list: `exec` and `shell` are single statements too.
@immutable
class YosysScriptRequest {
  /// Creates a script request.
  const YosysScriptRequest({required this.commands});

  /// The statements, in order. The runner appends `write_json`.
  final List<String> commands;

  @override
  bool operator ==(Object other) =>
      other is YosysScriptRequest && _listEq(other.commands, commands);

  @override
  int get hashCode => Object.hashAll(commands);

  @override
  String toString() => 'YosysScriptRequest(${commands.length} commands)';
}

/// The outcome of lowering a request's VHDL to Verilog on its own, with
/// `YosysRunner.lowerVhdl`. Sealed so a caller handles every case.
@immutable
sealed class VhdlLowerResult {
  const VhdlLowerResult({required this.stdout, required this.stderr});

  /// Captured stdout of `ghdl`; empty on success, where stdout is the
  /// emitted Verilog and went to the output file.
  final String stdout;

  /// Captured stderr of `ghdl`, its diagnostics.
  final String stderr;
}

/// `ghdl --synth --out=verilog` exited cleanly and wrote a non-empty Verilog
/// file at [outputPath].
@immutable
final class VhdlLowerSuccess extends VhdlLowerResult {
  /// Creates a success result.
  const VhdlLowerSuccess({
    required this.outputPath,
    required super.stdout,
    required super.stderr,
  });

  /// Where the emitted Verilog is: the path the caller gave. The caller owns
  /// the file.
  final String outputPath;
}

/// `ghdl` could not be run, exited non-zero, or emitted nothing. [kind] says
/// which, with the same vocabulary as [YosysRunFailure].
@immutable
final class VhdlLowerFailure extends VhdlLowerResult {
  /// Creates a failure result.
  const VhdlLowerFailure({
    required this.kind,
    required this.exitCode,
    required super.stdout,
    required super.stderr,
  });

  /// Why the lowering failed: [YosysFailureKind.launch] (no `ghdl`),
  /// [YosysFailureKind.invalidRequest] (no VHDL source, a bad unit name or
  /// standard), [YosysFailureKind.nonZeroExit], [YosysFailureKind.noOutput]
  /// or [YosysFailureKind.outputUnreadable].
  final YosysFailureKind kind;

  /// `ghdl`'s exit status, or `-1` when no process status exists.
  final int exitCode;
}

/// `ghdl` exceeded its time [budget] and was killed.
@immutable
final class VhdlLowerTimeout extends VhdlLowerResult {
  /// Creates a timeout result.
  const VhdlLowerTimeout({
    required this.budget,
    required super.stdout,
    required super.stderr,
  });

  /// The budget after which the runner killed the process.
  final Duration budget;
}

/// `ghdl` was killed because the caller's cancel signal fired.
@immutable
final class VhdlLowerCancelled extends VhdlLowerResult {
  /// Creates a cancelled result.
  const VhdlLowerCancelled({required super.stdout, required super.stderr});
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
