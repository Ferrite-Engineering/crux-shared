// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math';

import 'package:crux_yosys/src/process_runner.dart';
import 'package:crux_yosys/src/yosys_run.dart';
import 'package:path/path.dart' as p;

/// Spawns Yosys as a subprocess to elaborate one [YosysRunRequest] into a
/// `write_json` document.
///
/// For pure-Verilog requests the runner builds a script of the shape:
///
/// ```text
/// read_verilog [-I include] [-D define] file1.v file2.v ...
/// hierarchy -check [-top top_module]
/// proc
/// [extra commands]
/// write_json <temp file>
/// ```
///
/// For requests that contain any VHDL source (`YosysSourceFile.language
/// == vhdl`), the runner first lowers the VHDL to Verilog with a
/// *standalone* GHDL invocation (no Yosys GHDL plugin is involved):
///
/// ```text
/// ghdl --synth [--std=NN] --out=verilog vhdl_files -e <vhdlTopUnit>
/// ```
///
/// GHDL writes the synthesizable Verilog to stdout, which the runner
/// captures to a temp `.v` file. That emitted file is then read by Yosys
/// as an ordinary Verilog source, alongside any original Verilog sources,
/// so `hierarchy` binds a Verilog instantiation of a VHDL entity by
/// module name (the emitted module name is the VHDL entity name):
///
/// ```text
/// read_verilog [-sv] ... verilog_files ghdl_emitted.v
/// hierarchy -check [-top top_module]
/// proc
/// ...
/// ```
///
/// Yosys writes JSON to a temp file (passed as a script argument) rather
/// than to stdout because Yosys interleaves its own log output on stdout.
/// The runner reads the file, deletes it, and returns the contents via
/// [YosysRunSuccess.rawJson]. On failure (non-zero exit or empty JSON
/// output) a [YosysRunFailure] is returned with stdout/stderr captured so
/// the diagnostic parser can extract `file:line:col` messages, and a
/// [YosysFailureKind] saying which failure it was.
///
/// All filesystem and process touches go through injectable seams so
/// tests don't need a real Yosys binary: the [ProcessRunner] handles
/// subprocess spawning and the temp directory + filename are derived
/// from the `tempDirectory` constructor parameter.
class YosysRunner {
  /// Creates a runner.
  ///
  /// [ghdlExecutable] is the standalone GHDL binary used to lower VHDL
  /// sources to Verilog before Yosys runs. It defaults to `ghdl` on PATH;
  /// a consuming product can point it at a bundled or user-configured
  /// GHDL. It is only ever spawned for requests that contain VHDL.
  YosysRunner({
    ProcessRunner? processRunner,
    String? executable,
    String? ghdlExecutable,
    Directory? tempDirectory,
  }) : _processRunner = processRunner ?? const DefaultProcessRunner(),
       _executable = executable ?? _defaultExecutableName(),
       _ghdlExecutable = ghdlExecutable ?? _defaultGhdlExecutableName(),
       _tempDirectory = tempDirectory ?? Directory.systemTemp;

  final ProcessRunner _processRunner;
  final String _executable;
  final String _ghdlExecutable;
  final Directory _tempDirectory;

  static String _defaultExecutableName() =>
      Platform.isWindows ? 'yosys.exe' : 'yosys';

  static String _defaultGhdlExecutableName() =>
      Platform.isWindows ? 'ghdl.exe' : 'ghdl';

  /// Synthetic exit code reported when Yosys could not be run at all — the
  /// binary is missing, the request could not be turned into a valid script,
  /// or the temp JSON file could not be read back. No real Yosys exit status
  /// is available in those cases, so a value outside the range a process can
  /// return is used to keep it distinguishable from a genuine failure.
  ///
  /// **Three failures share it, and only one is a missing binary.** To tell
  /// them apart, branch on [YosysRunFailure.kind] —
  /// [YosysFailureKind.launch], [YosysFailureKind.invalidRequest] or
  /// [YosysFailureKind.outputUnreadable] — rather than on this value plus the
  /// wording of `stderr`. The value itself stays `-1` for existing callers.
  static const int launchFailureExitCode = -1;

  /// Runs Yosys to elaborate the given [request].
  ///
  /// **Always returns a [YosysRunResult]; never throws.** Callers pattern-
  /// match on success vs failure rather than wrapping this in a try/catch.
  /// In particular the most likely real-world failure — Yosys not installed,
  /// which makes the spawn raise a [ProcessException] — comes back as a
  /// [YosysRunFailure] of kind [YosysFailureKind.launch], with
  /// [launchFailureExitCode] and an explanatory `stderr`, not as a thrown
  /// exception in the caller's async context. The same holds for a request
  /// the script builder rejects (a path containing a double quote,
  /// [YosysFailureKind.invalidRequest]) and for an unreadable temp file
  /// ([YosysFailureKind.outputUnreadable]). Every failure this returns
  /// carries its [YosysRunFailure.kind] explicitly.
  ///
  /// [timeout] bounds the subprocess: if Yosys has not exited within the
  /// budget it is killed and a [YosysRunTimeout] is returned. [cancelSignal]
  /// kills the subprocess when it completes (tab close / superseding
  /// re-elaboration) and yields a [YosysRunCancelled]. In both kill cases
  /// the `write_json` temp file is still cleaned up by the `finally` below.
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
  }) async {
    final jsonFile = _allocateJsonFile();
    // Holds the ghdl-emitted Verilog for a VHDL request; cleaned up in the
    // finally alongside the JSON temp file. Null for pure-Verilog requests.
    File? loweredVerilogFile;
    // Holds the links to include directories whose paths contain whitespace;
    // removed in the finally. Null when no include directory needs one.
    Directory? includeLinkDirectory;
    try {
      // VHDL pre-synth: lower every VHDL source to Verilog with a
      // standalone `ghdl --synth` before Yosys ever runs. On any non-happy
      // outcome (killed, non-zero exit, empty emission) return early with
      // the ghdl diagnostics so the failure surfaces as a pipeline error.
      var effectiveRequest = request;
      if (request.hasVhdlSources) {
        loweredVerilogFile = _allocateVerilogFile();
        final ghdlResult = await _processRunner.run(
          _ghdlExecutable,
          buildGhdlSynthArguments(request),
          timeout: timeout,
          cancelSignal: cancelSignal,
          stdoutFilePath: loweredVerilogFile.path,
        );
        switch (ghdlResult.termination) {
          case ProcessTermination.timedOut:
            return YosysRunTimeout(
              budget: timeout ?? Duration.zero,
              stdout: ghdlResult.stdout,
              stderr: ghdlResult.stderr,
            );
          case ProcessTermination.cancelled:
            return YosysRunCancelled(
              stdout: ghdlResult.stdout,
              stderr: ghdlResult.stderr,
            );
          case ProcessTermination.exited:
            break;
        }
        if (ghdlResult.exitCode != 0) {
          return YosysRunFailure(
            kind: YosysFailureKind.nonZeroExit,
            exitCode: ghdlResult.exitCode,
            stdout: ghdlResult.stdout,
            stderr: ghdlResult.stderr.isEmpty
                ? 'ghdl --synth exited ${ghdlResult.exitCode} with no output'
                : ghdlResult.stderr,
          );
        }
        if (!loweredVerilogFile.existsSync() ||
            loweredVerilogFile.lengthSync() == 0) {
          return YosysRunFailure(
            kind: YosysFailureKind.noOutput,
            exitCode: ghdlResult.exitCode,
            stdout: ghdlResult.stdout,
            stderr: ghdlResult.stderr.isEmpty
                ? 'ghdl --synth exited cleanly but emitted no Verilog'
                : ghdlResult.stderr,
          );
        }
        effectiveRequest = _lowerVhdlToVerilog(
          request,
          loweredVerilogFile.path,
        );
      }
      final linked = _linkWhitespaceIncludeDirs(effectiveRequest);
      includeLinkDirectory = linked.directory;
      effectiveRequest = linked.request;
      final script = _buildScript(effectiveRequest, jsonFile.path);
      final processResult = await _runProcess(
        script,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onStderrLine: onStderrLine,
      );
      // A killed process is reported by its termination reason, not its
      // exit code — branch on that before the exit-code / empty-JSON
      // checks so a SIGKILL'd Yosys never masquerades as a plain failure.
      switch (processResult.termination) {
        case ProcessTermination.timedOut:
          return YosysRunTimeout(
            budget: timeout ?? Duration.zero,
            stdout: processResult.stdout,
            stderr: processResult.stderr,
          );
        case ProcessTermination.cancelled:
          return YosysRunCancelled(
            stdout: processResult.stdout,
            stderr: processResult.stderr,
          );
        case ProcessTermination.exited:
          break;
      }
      if (processResult.exitCode != 0) {
        return YosysRunFailure(
          kind: YosysFailureKind.nonZeroExit,
          exitCode: processResult.exitCode,
          stdout: processResult.stdout,
          stderr: processResult.stderr,
        );
      }
      if (!jsonFile.existsSync()) {
        return YosysRunFailure(
          kind: YosysFailureKind.noOutput,
          exitCode: processResult.exitCode,
          stdout: processResult.stdout,
          stderr: processResult.stderr.isEmpty
              ? 'Yosys exited cleanly but produced no JSON output'
              : processResult.stderr,
        );
      }
      final rawJson = jsonFile.readAsStringSync();
      if (rawJson.trim().isEmpty) {
        return YosysRunFailure(
          kind: YosysFailureKind.noOutput,
          exitCode: processResult.exitCode,
          stdout: processResult.stdout,
          stderr: processResult.stderr.isEmpty
              ? 'Yosys wrote an empty JSON file'
              : processResult.stderr,
        );
      }
      return YosysRunSuccess(
        rawJson: rawJson,
        stdout: processResult.stdout,
        stderr: processResult.stderr,
      );
    } on ProcessException catch (e) {
      // Yosys (or, for a VHDL request, ghdl) is not installed, not on PATH,
      // or not executable. This is the single most common real-world
      // failure and it must not surface as a thrown exception — the
      // documented contract is that callers can pattern-match every
      // outcome. The executable name comes from the exception so the
      // message names whichever tool actually failed to spawn.
      return YosysRunFailure(
        kind: YosysFailureKind.launch,
        exitCode: launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "${e.executable}": ${e.message}',
      );
      // Deliberately catching an Error. `_escape` signals a rejected path or
      // identifier with ArgumentError, which is the right signal for the
      // synchronous `buildScript` entry point but would breach this method's
      // documented never-throws contract. The value comes from the user's
      // own file paths, so it is input validation rather than a programming
      // error, and it belongs in the result type.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (e) {
      return YosysRunFailure(
        kind: YosysFailureKind.invalidRequest,
        exitCode: launchFailureExitCode,
        stdout: '',
        stderr: 'Invalid Yosys request: ${e.message}',
      );
    } on FileSystemException catch (e) {
      // The write_json temp file could not be read back (removed underneath
      // us, permissions, full disk).
      return YosysRunFailure(
        kind: YosysFailureKind.outputUnreadable,
        exitCode: launchFailureExitCode,
        stdout: '',
        stderr: 'Could not read the Yosys JSON output: ${e.message}',
      );
    } finally {
      // Best-effort cleanup; ignore if a file was never created.
      for (final file in <File?>[jsonFile, loweredVerilogFile]) {
        if (file != null && file.existsSync()) {
          try {
            file.deleteSync();
          } on FileSystemException {
            // Ignore — leftover temp files are not fatal.
          }
        }
      }
      final linkDirectory = includeLinkDirectory;
      if (linkDirectory != null) _removeLinkDirectory(linkDirectory);
    }
  }

  /// Gives every include directory whose path contains whitespace a
  /// whitespace-free alias: a link (a symlink, or a junction on Windows)
  /// inside a fresh per-run directory under the temp directory. Yosys cannot
  /// take such a path as `-I` at all (see [_bareOption]), and a folder name
  /// with a space in it is common on every desktop platform.
  ///
  /// Returns [request] unchanged, with no directory, when nothing needs a
  /// link. An include directory whose link cannot be created keeps its own
  /// path, so [_buildScript] refuses it with a message naming the path
  /// instead of the run failing on an unrelated file-system error.
  ({YosysRunRequest request, Directory? directory}) _linkWhitespaceIncludeDirs(
    YosysRunRequest request,
  ) {
    if (!request.includePaths.any(_hasWhitespace)) {
      return (request: request, directory: null);
    }
    final directory = Directory(_allocateTempPath('inc'))..createSync();
    final includePaths = <String>[];
    for (final (index, include) in request.includePaths.indexed) {
      if (!_hasWhitespace(include)) {
        includePaths.add(include);
        continue;
      }
      try {
        final link = Link(p.join(directory.path, 'i$index'))
          ..createSync(p.absolute(include));
        includePaths.add(link.path);
      } on FileSystemException {
        includePaths.add(include);
      }
    }
    return (
      request: YosysRunRequest(
        sources: request.sources,
        topModule: request.topModule,
        defines: request.defines,
        includePaths: includePaths,
        extraCommands: request.extraCommands,
        vhdlStandard: request.vhdlStandard,
        vhdlTopUnit: request.vhdlTopUnit,
      ),
      directory: directory,
    );
  }

  /// Removes the links [_linkWhitespaceIncludeDirs] made, then their
  /// directory. Only links are deleted and the directory is removed
  /// non-recursively, so nothing a link points at is ever touched.
  static void _removeLinkDirectory(Directory directory) {
    try {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is Link) entity.deleteSync();
      }
      directory.deleteSync();
    } on FileSystemException {
      // Ignore — a leftover temp directory is not fatal.
    }
  }

  Future<ProcessRunResult> _runProcess(
    String script, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
  }) {
    return _processRunner.run(
      _executable,
      <String>['-q', '-p', script],
      timeout: timeout,
      cancelSignal: cancelSignal,
      onStderrLine: onStderrLine,
    );
  }

  static final Random _random = Random();

  /// Picks a unique path for the `write_json` output.
  ///
  /// The name carries the process id and a random suffix as well as a
  /// timestamp. A timestamp alone is not enough: two products in the suite
  /// can elaborate concurrently against the same system temp directory and
  /// land on the same microsecond, and the loser's cleanup `finally` would
  /// then delete the winner's output while the winner is still reading it.
  File _allocateJsonFile() => _allocateTempFile('json');

  /// Picks a unique path for the ghdl-emitted Verilog, using the same
  /// collision-proof naming as [_allocateJsonFile].
  File _allocateVerilogFile() => _allocateTempFile('v');

  File _allocateTempFile(String extension) =>
      File(_allocateTempPath(extension));

  String _allocateTempPath(String extension) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    final name = 'crux_yosys_${pid}_${stamp}_$salt.$extension';
    return p.join(_tempDirectory.path, name);
  }

  /// Builds the script passed via `yosys -p`. Returns a single string
  /// where commands are separated by `;` (Yosys's statement separator).
  ///
  /// Exposed at library scope (via [buildScript]) so tests and the
  /// consuming-product verification helpers can assert on the exact
  /// script the runner would emit without spawning a subprocess.
  static String _buildScript(YosysRunRequest request, String jsonOutputPath) {
    final verilogSources = <YosysSourceFile>[];
    final systemVerilogSources = <YosysSourceFile>[];
    for (final src in request.sources) {
      switch (src.language) {
        case YosysSourceLanguage.verilog:
          verilogSources.add(src);
        case YosysSourceLanguage.systemVerilog:
          systemVerilogSources.add(src);
        case YosysSourceLanguage.vhdl:
          // VHDL is lowered to Verilog by `ghdl --synth` in run() before
          // the script is built; a VHDL source reaching the pure-script
          // builder has no read command and is ignored here.
          break;
      }
    }

    final commands = <String>[];

    // Verilog read (1995/2001/2005). `-I` and `-D` are Verilog
    // preprocessor flags, so they go on this read command. Their values are
    // emitted bare and file names quoted; see [_bareOption] for why.
    if (verilogSources.isNotEmpty) {
      final readBuffer = StringBuffer('read_verilog');
      for (final inc in request.includePaths) {
        readBuffer.write(' -I ${_bareOption(inc, 'Include path')}');
      }
      for (final def in request.defines) {
        readBuffer.write(' -D ${_bareOption(def, 'Define')}');
      }
      for (final file in verilogSources) {
        readBuffer.write(' "${_escape(file.path)}"');
      }
      commands.add(readBuffer.toString());
    }

    // SystemVerilog read uses `-sv`. Emitted as a separate command so
    // Yosys parses each file under the correct dialect.
    if (systemVerilogSources.isNotEmpty) {
      final readBuffer = StringBuffer('read_verilog -sv');
      for (final inc in request.includePaths) {
        readBuffer.write(' -I ${_bareOption(inc, 'Include path')}');
      }
      for (final def in request.defines) {
        readBuffer.write(' -D ${_bareOption(def, 'Define')}');
      }
      for (final file in systemVerilogSources) {
        readBuffer.write(' "${_escape(file.path)}"');
      }
      commands.add(readBuffer.toString());
    }

    final hierarchy = StringBuffer('hierarchy -check');
    if (request.topModule != null && request.topModule!.isNotEmpty) {
      hierarchy.write(' -top ${_identifier(request.topModule!)}');
    } else {
      // No explicit top: let Yosys pick the top-of-design AND mark it with
      // the `(* top *)` attribute. Without `-auto-top` (or an explicit
      // `-top`), `hierarchy` designates no top, `write_json` emits no
      // top-marked module, and the viewer reports "the elaborated design
      // has no top module" for every loose-source open. `-auto-top` selects
      // the module instantiated by nothing else — the conventional root.
      hierarchy.write(' -auto-top');
    }
    commands
      ..add(hierarchy.toString())
      ..add('proc')
      ..addAll(request.extraCommands)
      ..add('write_json "${_escape(jsonOutputPath)}"');
    return commands.join('; ');
  }

  /// Library-public entry point for tests / verification helpers that
  /// want to inspect the exact script the runner would invoke. Pure;
  /// does not spawn a subprocess.
  ///
  /// Only Verilog / SystemVerilog sources produce read commands. VHDL is
  /// lowered to Verilog out-of-band (see [buildGhdlSynthArguments]) before
  /// the request reaches the script builder, so a raw request that still
  /// carries VHDL sources yields a script with no read command for them.
  static String buildScript(
    YosysRunRequest request, {
    required String jsonOutputPath,
  }) => _buildScript(request, jsonOutputPath);

  /// Builds the argument list for the standalone `ghdl --synth` invocation
  /// that lowers a request's VHDL sources to Verilog on stdout. Pure; does
  /// not spawn a subprocess, so tests can assert the exact command.
  ///
  /// Shape: `--synth [--std=NN] --out=verilog <vhdl files…> -e <topUnit>`.
  /// The top unit is [YosysRunRequest.vhdlTopUnit], falling back to
  /// [YosysRunRequest.topModule] then `top`. Arguments are passed to
  /// `Process.start` verbatim (no shell), so paths need no quoting; only
  /// the elaborated unit name is validated as a bare identifier, and the
  /// standard (when set) as a short `--std` token.
  static List<String> buildGhdlSynthArguments(YosysRunRequest request) {
    final args = <String>['--synth'];
    final std = request.vhdlStandard;
    if (std != null && std.isNotEmpty) {
      args.add('--std=${_stdValue(std)}');
    }
    args.add('--out=verilog');
    for (final src in request.sources) {
      if (src.language == YosysSourceLanguage.vhdl) {
        args.add(src.path);
      }
    }
    final topUnit = request.vhdlTopUnit ?? request.topModule ?? 'top';
    args
      ..add('-e')
      ..add(_identifier(topUnit));
    return args;
  }

  /// Returns a copy of [request] with its VHDL sources replaced by a single
  /// Verilog source at [emittedVerilogPath] (the `ghdl --synth` output).
  /// Original Verilog / SystemVerilog sources keep their order and precede
  /// the emitted file, so a Verilog blackbox prototype of a VHDL entity is
  /// overridden by the real emitted module during `hierarchy`.
  static YosysRunRequest _lowerVhdlToVerilog(
    YosysRunRequest request,
    String emittedVerilogPath,
  ) {
    return YosysRunRequest(
      sources: <YosysSourceFile>[
        for (final src in request.sources)
          if (src.language != YosysSourceLanguage.vhdl) src,
        YosysSourceFile(emittedVerilogPath),
      ],
      topModule: request.topModule,
      defines: request.defines,
      includePaths: request.includePaths,
      extraCommands: request.extraCommands,
    );
  }

  /// Validates a file path that will be emitted double-quoted into the `-p`
  /// script. File names are wrapped in `"…"` so embedded spaces survive
  /// Yosys's tokenizer; `read_verilog` and `write_json` strip the quotes from
  /// file names. Quoting cannot make every character safe, though: a `"`
  /// would terminate the quoted region, and `;` / newlines split the `-p`
  /// string into commands regardless of quoting. Those are refused loudly
  /// rather than emitted as a silently corrupted script; callers will not
  /// normally hit this with real designs. [_bareOption] applies the same
  /// checks to option values.
  static String _escape(String value) {
    const forbidden = ['"', ';', '\n', '\r'];
    for (final ch in forbidden) {
      if (value.contains(ch)) {
        throw ArgumentError.value(
          value,
          'value',
          'Path or define must not contain double quotes, semicolons, '
              'or newlines',
        );
      }
    }
    return value;
  }

  /// Validates an option value emitted BARE (unquoted) into the `-p` script:
  /// `read_verilog -I <dir>` and `-D <NAME[=VALUE]>`. Yosys's tokenizer keeps
  /// double quotes inside a token and `read_verilog` strips them only from
  /// file names, so a quoted `-I "dir"` registers a directory literally named
  /// `"dir"` (no include is ever found) and a quoted `-D "FOO=1"` defines a
  /// macro named `"FOO`. Unquoted, a value cannot contain whitespace either:
  /// [run] reaches an include directory with whitespace through a link (see
  /// [_linkWhitespaceIncludeDirs]), and a define with whitespace cannot be
  /// expressed, so it is refused rather than passed as a broken token.
  static String _bareOption(String value, String what) {
    _escape(value);
    if (_hasWhitespace(value)) {
      throw ArgumentError.value(
        value,
        'value',
        '$what must not contain whitespace: a Yosys script cannot pass it '
            'to read_verilog',
      );
    }
    return value;
  }

  static final RegExp _whitespacePattern = RegExp(r'\s');

  static bool _hasWhitespace(String value) =>
      _whitespacePattern.hasMatch(value);

  static final RegExp _identifierPattern = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$.]*$',
  );

  /// Validates a module/unit identifier that is emitted BARE (unquoted)
  /// into the `-p` script — `hierarchy -top <name>` and `ghdl -e <name>`.
  /// Yosys treats surrounding quotes as part of the module name
  /// (`-top "and2"` looks for a module literally named `"and2"` and fails),
  /// so identifiers must not be quoted. A well-formed HDL top is a bare
  /// identifier with no whitespace, so bare emission is safe; anything that
  /// is not a valid identifier (spaces, quotes, `;`, shell metacharacters)
  /// is refused loudly rather than corrupting the script.
  static String _identifier(String value) {
    if (!_identifierPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Module/unit name must be a bare HDL identifier '
            r'(letters, digits, _, $, . — no whitespace or metacharacters)',
      );
    }
    return value;
  }

  static final RegExp _stdPattern = RegExp(r'^[0-9a-z]+$');

  /// Validates the VHDL standard token emitted as `--std=<value>` to ghdl.
  /// GHDL standard selectors are short alphanumerics (`87`, `93`, `93c`,
  /// `08`, `19`); reject anything else rather than pass an arbitrary string
  /// to the subprocess.
  static String _stdValue(String value) {
    if (!_stdPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'vhdlStandard',
        'VHDL standard must be a short ghdl --std token '
            '(e.g. 87, 93, 93c, 08, 19)',
      );
    }
    return value;
  }
}
