// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// Fake runner that inspects the yosys script supplied via `-p` to find
/// the `write_json <path>` target, then optionally writes synthetic JSON
/// to that path so the runner thinks Yosys produced output.
class _FakeRunner implements ProcessRunner {
  _FakeRunner({
    required this.exitCode,
    this.jsonToWrite,
    this.jsonBytesToWrite,
    this.stdout = '',
    this.stderr = '',
    this.termination = ProcessTermination.exited,
    this.ghdlExitCode = 0,
    this.ghdlStderr = '',
    this.ghdlVerilog = 'module lowered(); endmodule\n',
    this.ghdlTermination = ProcessTermination.exited,
  });

  final int exitCode;
  final String? jsonToWrite;

  /// Raw bytes to write instead of [jsonToWrite], for output that is not
  /// valid UTF-8.
  final List<int>? jsonBytesToWrite;
  final String stdout;
  final String stderr;
  final ProcessTermination termination;

  // Behavior for the standalone `ghdl --synth` pre-step (only reached for
  // requests that contain VHDL). The fake writes [ghdlVerilog] to the
  // stdoutFilePath the runner supplies, mimicking a real ghdl emission.
  final int ghdlExitCode;
  final String ghdlStderr;
  final String ghdlVerilog;
  final ProcessTermination ghdlTermination;

  String? capturedScript;
  String? capturedGhdlExecutable;
  List<String>? capturedGhdlArgs;
  Duration? capturedTimeout;
  Future<void>? capturedCancelSignal;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    // The VHDL pre-synth step streams its stdout to a file; that is how we
    // recognize the ghdl invocation vs the yosys invocation.
    if (stdoutFilePath != null) {
      capturedGhdlExecutable = executable;
      capturedGhdlArgs = arguments;
      capturedTimeout = timeout;
      capturedCancelSignal = cancelSignal;
      if (ghdlTermination == ProcessTermination.exited && ghdlExitCode == 0) {
        File(stdoutFilePath).writeAsStringSync(ghdlVerilog);
      }
      return ProcessRunResult(
        exitCode: ghdlExitCode,
        stdout: '',
        stderr: ghdlStderr,
        termination: ghdlTermination,
      );
    }
    // Yosys is invoked as: yosys -q -p "<script>"
    final pIndex = arguments.indexOf('-p');
    expect(
      pIndex,
      isNonNegative,
      reason: 'YosysRunner must invoke yosys with -p',
    );
    final script = arguments[pIndex + 1];
    capturedScript = script;
    capturedTimeout = timeout;
    capturedCancelSignal = cancelSignal;
    if (jsonToWrite != null || jsonBytesToWrite != null) {
      final match = RegExp(r'write_json\s+"([^"]+)"').firstMatch(script);
      expect(
        match,
        isNotNull,
        reason: 'Script must contain a write_json invocation',
      );
      final path = match!.group(1)!;
      final bytes = jsonBytesToWrite;
      if (bytes != null) {
        File(path).writeAsBytesSync(bytes);
      } else {
        File(path).writeAsStringSync(jsonToWrite!);
      }
    }
    return ProcessRunResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      termination: termination,
    );
  }
}

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crux_yosys_runner_test_');
  });
  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('YosysRunner', () {
    test('produces YosysRunSuccess with the JSON Yosys wrote', () async {
      const json = '{"creator": "Yosys 0.50", "modules": {}}';
      final runner = YosysRunner(
        processRunner: _FakeRunner(
          exitCode: 0,
          jsonToWrite: json,
          stdout: 'compile log',
        ),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );
      expect(result, isA<YosysRunSuccess>());
      expect((result as YosysRunSuccess).rawJson, json);
      expect(result.stdout, 'compile log');
    });

    test('emits a YosysRunFailure when yosys exits non-zero', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(
          exitCode: 2,
          stderr: 'foo.v:3: ERROR: syntax error',
        ),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );
      expect(result, isA<YosysRunFailure>());
      expect((result as YosysRunFailure).exitCode, 2);
      expect(result.kind, YosysFailureKind.nonZeroExit);
      expect(result.stderr, contains('ERROR'));
    });

    test('treats missing JSON as failure even when exit code is 0', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(
          exitCode: 0,
          // jsonToWrite is null — fake runner won't touch the file
          stderr: 'some warning',
        ),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );
      expect(result, isA<YosysRunFailure>());
      expect((result as YosysRunFailure).stderr, contains('some warning'));
      expect(result.kind, YosysFailureKind.noOutput);
      expect(result.exitCode, 0);
    });

    test('treats empty JSON file as failure', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(exitCode: 0, jsonToWrite: '   '),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );
      expect(result, isA<YosysRunFailure>());
      expect((result as YosysRunFailure).kind, YosysFailureKind.noOutput);
    });

    test(
      'a write_json file that cannot be read back is outputUnreadable',
      () async {
        // Not UTF-8, so reading it back raises a FileSystemException after a
        // clean exit. No process status describes that, so it shares the
        // synthetic exit code — and the kind is what tells it apart from a
        // missing binary.
        final runner = YosysRunner(
          processRunner: _FakeRunner(
            exitCode: 0,
            jsonBytesToWrite: const <int>[0xFF, 0xFE, 0xFD],
          ),
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        final result = await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
          ),
        );
        expect(result, isA<YosysRunFailure>());
        final failure = result as YosysRunFailure;
        expect(failure.kind, YosysFailureKind.outputUnreadable);
        expect(failure.exitCode, YosysRunner.launchFailureExitCode);
      },
    );

    test(
      'builds a script with read_verilog, hierarchy, proc, write_json',
      () async {
        final fake = _FakeRunner(exitCode: 0, jsonToWrite: '{}');
        final runner = YosysRunner(
          processRunner: fake,
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[
              YosysSourceFile('/tmp/foo.v'),
              YosysSourceFile('/tmp/bar.v'),
            ],
            topModule: 'top',
            defines: ['FOO=1', 'BAR'],
            includePaths: ['/tmp/inc'],
            extraCommands: ['flatten'],
          ),
        );
        final script = fake.capturedScript!;
        expect(script, contains('read_verilog'));
        // Option values are bare: Yosys keeps quotes inside -I / -D values.
        expect(script, contains('-I /tmp/inc '));
        expect(script, contains('-D FOO=1 '));
        expect(script, contains('-D BAR '));
        expect(script, isNot(contains('-I "')));
        expect(script, isNot(contains('-D "')));
        expect(script, contains('"/tmp/foo.v"'));
        expect(script, contains('"/tmp/bar.v"'));
        expect(script, contains('hierarchy -check -top top'));
        expect(script, contains('proc'));
        expect(script, contains('flatten'));
        expect(script, contains('write_json'));
      },
    );

    test(
      'uses -auto-top (not an explicit -top) when topModule is null',
      () async {
        final fake = _FakeRunner(exitCode: 0, jsonToWrite: '{}');
        final runner = YosysRunner(
          processRunner: fake,
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
          ),
        );
        // Without an explicit top, Yosys must still mark a top-of-design via
        // -auto-top so write_json emits a (* top *) module and the viewer can
        // root the hierarchy. No explicit `-top <name>` is emitted.
        expect(fake.capturedScript, contains('hierarchy -check -auto-top'));
        expect(fake.capturedScript, isNot(contains('-top ')));
      },
    );

    test(
      'rejects paths containing double quotes as a failure result',
      () async {
        // `run` documents that it never throws. A source path containing a
        // double quote is user-supplied input, not a programming error, so it
        // must come back as a YosysRunFailure the caller can pattern-match —
        // not as an ArgumentError escaping into the caller's async context.
        final runner = YosysRunner(
          processRunner: _FakeRunner(exitCode: 0, jsonToWrite: '{}'),
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        final result = await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/bad"name.v')],
          ),
        );
        expect(result, isA<YosysRunFailure>());
        expect(
          (result as YosysRunFailure).exitCode,
          YosysRunner.launchFailureExitCode,
        );
        expect(
          result.kind,
          YosysFailureKind.invalidRequest,
          reason: 'same exit code as a missing binary, but nothing is missing',
        );
        expect(result.stderr, contains('double quotes'));
      },
    );

    test('quotes file names against spaces', () {
      // read_verilog strips the quotes from a file name, so a path with a
      // space survives the tokenizer only when quoted.
      final script = YosysRunner.buildScript(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/my design/foo.v')],
        ),
        jsonOutputPath: '/tmp/out.json',
      );
      expect(script, contains('"/tmp/my design/foo.v"'));
    });

    test('refuses a define or an include path that contains whitespace', () {
      // An option value is emitted bare, and Yosys would split one with a
      // space into two arguments, silently changing the elaboration.
      expect(
        () => YosysRunner.buildScript(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
            defines: ['MSG=hello world'],
          ),
          jsonOutputPath: '/tmp/out.json',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Define must not contain whitespace'),
          ),
        ),
      );
      expect(
        () => YosysRunner.buildScript(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
            includePaths: ['/tmp/my includes'],
          ),
          jsonOutputPath: '/tmp/out.json',
        ),
        throwsArgumentError,
      );
    });

    test(
      'run reaches an include directory with whitespace through a link',
      () async {
        final includes = Directory('${tempDir.path}/my includes')..createSync();
        final fake = _FakeRunner(exitCode: 0, jsonToWrite: '{}');
        final runner = YosysRunner(
          processRunner: fake,
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        final result = await runner.run(
          YosysRunRequest(
            sources: const <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
            includePaths: <String>['/tmp/plain', includes.path],
          ),
        );
        expect(result, isA<YosysRunSuccess>());
        final script = fake.capturedScript!;
        expect(script, contains('-I /tmp/plain '));
        final linked = RegExp(r'-I (\S+)')
            .allMatches(script)
            .map((m) => m.group(1)!)
            .where((path) => path != '/tmp/plain')
            .toList();
        expect(linked, hasLength(1));
        final linkPath = linked.single;
        expect(linkPath, isNot(contains(' ')));
        expect(linkPath, startsWith(tempDir.path));
        // The link is gone after the run; what it pointed at is not.
        expect(Link(linkPath).existsSync(), isFalse);
        expect(Directory(linkPath).parent.existsSync(), isFalse);
        expect(includes.existsSync(), isTrue);
      },
    );

    test('a define with whitespace comes back from run as a failure', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(exitCode: 0, jsonToWrite: '{}'),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
          defines: ['MSG=hello world'],
        ),
      );
      expect(result, isA<YosysRunFailure>());
      expect((result as YosysRunFailure).kind, YosysFailureKind.invalidRequest);
      expect(result.stderr, contains('whitespace'));
    });

    test('emits the hierarchy -top and ghdl -e units BARE (unquoted)', () {
      // Yosys treats quotes as part of the module name: `-top "and2"` looks
      // for a module literally named `"and2"` and fails. GHDL likewise wants
      // a bare `-e <unit>`. Both are validated identifiers, emitted bare.
      final script = YosysRunner.buildScript(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/top.v')],
          topModule: 'top_verilog',
        ),
        jsonOutputPath: '/tmp/out.json',
      );
      expect(script, contains('hierarchy -check -top top_verilog'));
      expect(script, isNot(contains('-top "')));

      final ghdlArgs = YosysRunner.buildGhdlSynthArguments(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          vhdlTopUnit: 'vhdl_entity',
        ),
      );
      // `-e` and the bare unit name are adjacent, un-quoted arguments.
      final eIndex = ghdlArgs.indexOf('-e');
      expect(eIndex, isNonNegative);
      expect(ghdlArgs[eIndex + 1], 'vhdl_entity');
    });

    test('rejects a top module / ghdl unit that is not a bare identifier', () {
      // A name with a space, quote, or metacharacter cannot be a real HDL
      // top; refuse loudly rather than emit a corrupted script / command.
      expect(
        () => YosysRunner.buildScript(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
            topModule: 'top module',
          ),
          jsonOutputPath: '/tmp/out.json',
        ),
        throwsArgumentError,
      );
      expect(
        () => YosysRunner.buildGhdlSynthArguments(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
            vhdlTopUnit: 'vhdl unit',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects semicolons and newlines in interpolated arguments', () {
      // `;` splits the -p string into separate Yosys commands regardless of
      // quoting, so a define like `X=1; shell rm` would inject a command.
      // Refused loudly rather than emitted as a corrupted script.
      YosysRunRequest withDefine(String d) => YosysRunRequest(
        sources: const <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        defines: [d],
      );
      expect(
        () => YosysRunner.buildScript(
          withDefine('EVIL=1; shell rm -rf /'),
          jsonOutputPath: '/tmp/out.json',
        ),
        throwsArgumentError,
      );
      expect(
        () => YosysRunner.buildScript(
          withDefine('EVIL=1\nshell'),
          jsonOutputPath: '/tmp/out.json',
        ),
        throwsArgumentError,
      );
      expect(
        () => YosysRunner.buildScript(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
            topModule: 'top; delete',
          ),
          jsonOutputPath: '/tmp/out.json',
        ),
        throwsArgumentError,
      );
    });

    test(
      'a semicolon-bearing argument comes back from run as a failure',
      () async {
        // Same never-throws contract as the double-quote case: user-supplied
        // input must surface as a YosysRunFailure, not an escaping
        // ArgumentError.
        final runner = YosysRunner(
          processRunner: _FakeRunner(exitCode: 0, jsonToWrite: '{}'),
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        final result = await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
            defines: ['EVIL=1; shell rm'],
          ),
        );
        expect(result, isA<YosysRunFailure>());
        expect(
          (result as YosysRunFailure).kind,
          YosysFailureKind.invalidRequest,
        );
      },
    );

    test(
      'a missing Yosys binary comes back as a failure, not a throw',
      () async {
        // The single most likely real-world failure. Process.start raises a
        // ProcessException; if the runner does not catch it, every caller that
        // elaborates without probing first crashes instead of showing a
        // "Yosys not found" diagnostic.
        final runner = YosysRunner(
          processRunner: _ThrowingRunner(
            const ProcessException('yosys', <String>[], 'No such file', 2),
          ),
          executable: 'yosys',
          tempDirectory: tempDir,
        );
        final result = await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
          ),
        );
        expect(result, isA<YosysRunFailure>());
        final failure = result as YosysRunFailure;
        expect(failure.exitCode, YosysRunner.launchFailureExitCode);
        expect(failure.kind, YosysFailureKind.launch);
        expect(failure.stderr, contains('yosys'));
        expect(failure.stderr, contains('No such file'));
      },
    );

    test('a missing ghdl for a VHDL request is a launch failure too', () async {
      final runner = YosysRunner(
        processRunner: _ThrowingRunner(
          const ProcessException('ghdl', <String>[], 'No such file', 2),
        ),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          topModule: 'a',
        ),
      );
      expect(result, isA<YosysRunFailure>());
      final failure = result as YosysRunFailure;
      expect(failure.kind, YosysFailureKind.launch);
      expect(failure.exitCode, YosysRunner.launchFailureExitCode);
      expect(failure.stderr, contains('ghdl'));
    });

    test('a launch failure still cleans up its temp file', () async {
      final runner = YosysRunner(
        processRunner: _ThrowingRunner(
          const ProcessException('yosys', <String>[], 'No such file', 2),
        ),
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );
      expect(tempDir.listSync(), isEmpty);
    });

    test('temp file names do not collide across concurrent runs', () async {
      // Two products elaborating at once against the same system temp
      // directory previously landed on the same microsecond-stamped name,
      // and the loser's cleanup deleted the winner's output mid-read.
      final names = <String>{};
      final fake = _NameCapturingRunner(names);
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      const request = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
      );
      await Future.wait<void>(<Future<void>>[
        for (var i = 0; i < 50; i++) runner.run(request),
      ]);
      expect(
        names,
        hasLength(50),
        reason: 'every concurrent run must get its own write_json path',
      );
    });

    test('builds a VHDL-only ghdl --synth command over all VHDL files', () {
      final args = YosysRunner.buildGhdlSynthArguments(
        const YosysRunRequest(
          sources: <YosysSourceFile>[
            YosysSourceFile.vhdl('/tmp/a.vhd'),
            YosysSourceFile.vhdl('/tmp/b.vhd'),
          ],
          topModule: 'mytop',
        ),
      );
      // Standalone synthesis to Verilog on stdout — no Yosys plugin.
      expect(args, containsAllInOrder(<String>['--synth', '--out=verilog']));
      // All VHDL files, in declaration order, then the elaborated unit.
      expect(
        args,
        containsAllInOrder(<String>['/tmp/a.vhd', '/tmp/b.vhd', '-e', 'mytop']),
      );
      // No --std flag unless the request asks for one.
      expect(args.any((a) => a.startsWith('--std=')), isFalse);
    });

    test('emits --std when a VHDL standard is requested', () {
      final args = YosysRunner.buildGhdlSynthArguments(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          topModule: 'mytop',
          vhdlStandard: '08',
        ),
      );
      expect(args, contains('--std=08'));
    });

    test('rejects a malformed VHDL standard token', () {
      expect(
        () => YosysRunner.buildGhdlSynthArguments(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
            vhdlStandard: '08; rm -rf /',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('vhdlTopUnit overrides topModule on the ghdl -e unit', () {
      final args = YosysRunner.buildGhdlSynthArguments(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          topModule: 'top_verilog',
          vhdlTopUnit: 'vhdl_entity',
        ),
      );
      final eIndex = args.indexOf('-e');
      expect(args[eIndex + 1], 'vhdl_entity');
    });

    test('vhdl top falls back to "top" when neither top is set', () {
      final args = YosysRunner.buildGhdlSynthArguments(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
        ),
      );
      final eIndex = args.indexOf('-e');
      expect(args[eIndex + 1], 'top');
    });

    test(
      'a VHDL request lowers via ghdl --synth, then Yosys reads Verilog only',
      () async {
        final fake = _FakeRunner(
          exitCode: 0,
          jsonToWrite: '{"modules": {"sub": {}, "top": {}}}',
          ghdlVerilog: 'module sub(); endmodule\n',
        );
        final runner = YosysRunner(
          processRunner: fake,
          executable: 'yosys',
          ghdlExecutable: 'ghdl',
          tempDirectory: tempDir,
        );
        final result = await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[
              YosysSourceFile('/tmp/top.v'),
              YosysSourceFile.vhdl('/tmp/sub.vhd'),
            ],
            topModule: 'top',
            vhdlTopUnit: 'sub',
          ),
        );
        expect(result, isA<YosysRunSuccess>());
        // ghdl was invoked as the standalone synth pre-step.
        expect(fake.capturedGhdlExecutable, 'ghdl');
        expect(
          fake.capturedGhdlArgs,
          containsAllInOrder(<String>[
            '--synth',
            '--out=verilog',
            '/tmp/sub.vhd',
            '-e',
            'sub',
          ]),
        );
        // The Yosys script reads Verilog (the original top.v + the emitted
        // module) and loads NO ghdl plugin.
        final script = fake.capturedScript!;
        expect(script, contains('read_verilog'));
        expect(script, contains('"/tmp/top.v"'));
        expect(script, isNot(contains('plugin -i ghdl')));
        expect(script, isNot(contains('read_vhdl')));
        expect(script, contains('hierarchy -check -top top'));
      },
    );

    test('a ghdl --synth non-zero exit surfaces as YosysRunFailure', () async {
      final fake = _FakeRunner(
        exitCode: 0,
        jsonToWrite: '{}',
        ghdlExitCode: 1,
        ghdlStderr: 'sub.vhd:5:1: syntax error',
      );
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          topModule: 'a',
        ),
      );
      expect(result, isA<YosysRunFailure>());
      final failure = result as YosysRunFailure;
      expect(failure.exitCode, 1);
      expect(failure.kind, YosysFailureKind.nonZeroExit);
      expect(failure.stderr, contains('syntax error'));
      // Yosys must not have run after the ghdl failure.
      expect(fake.capturedScript, isNull);
    });

    test('a ghdl --synth that emits no Verilog is noOutput', () async {
      final fake = _FakeRunner(exitCode: 0, jsonToWrite: '{}', ghdlVerilog: '');
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          topModule: 'a',
        ),
      );
      expect(result, isA<YosysRunFailure>());
      final failure = result as YosysRunFailure;
      expect(failure.kind, YosysFailureKind.noOutput);
      expect(failure.exitCode, 0);
      expect(fake.capturedScript, isNull);
    });

    test('a killed ghdl --synth maps to YosysRunTimeout', () async {
      final fake = _FakeRunner(
        exitCode: 0,
        jsonToWrite: '{}',
        ghdlExitCode: -9,
        ghdlStderr: 'killed',
        ghdlTermination: ProcessTermination.timedOut,
      );
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/a.vhd')],
          topModule: 'a',
        ),
        timeout: const Duration(seconds: 3),
      );
      expect(result, isA<YosysRunTimeout>());
      expect((result as YosysRunTimeout).budget, const Duration(seconds: 3));
      // Yosys must not have run after ghdl was killed.
      expect(fake.capturedScript, isNull);
    });

    test('SystemVerilog sources emit a read_verilog -sv block', () {
      final script = YosysRunner.buildScript(
        const YosysRunRequest(
          sources: <YosysSourceFile>[
            YosysSourceFile('/tmp/legacy.v'),
            YosysSourceFile.systemVerilog('/tmp/modern.sv'),
          ],
        ),
        jsonOutputPath: '/tmp/out.json',
      );
      // Verilog block first, SystemVerilog with -sv second.
      final verilogIdx = script.indexOf('read_verilog ');
      final svIdx = script.indexOf('read_verilog -sv');
      expect(verilogIdx, isNonNegative);
      expect(svIdx, greaterThan(verilogIdx));
      expect(script, contains('"/tmp/legacy.v"'));
      expect(script, contains('"/tmp/modern.sv"'));
    });

    test('cleans up the JSON temp file after a successful run', () async {
      final fake = _FakeRunner(exitCode: 0, jsonToWrite: '{}');
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );
      // Inspect the script for the write_json path, then assert the file
      // is gone after the run.
      final match = RegExp(
        r'write_json\s+"([^"]+)"',
      ).firstMatch(fake.capturedScript!);
      final jsonPath = match!.group(1)!;
      expect(File(jsonPath).existsSync(), isFalse);
    });

    test('forwards timeout and cancelSignal to the process runner', () async {
      final fake = _FakeRunner(exitCode: 0, jsonToWrite: '{}');
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final cancel = Completer<void>().future;
      await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
        timeout: const Duration(seconds: 42),
        cancelSignal: cancel,
      );
      expect(fake.capturedTimeout, const Duration(seconds: 42));
      expect(fake.capturedCancelSignal, same(cancel));
    });

    test('maps a timedOut termination to YosysRunTimeout', () async {
      final fake = _FakeRunner(
        exitCode: -9,
        stderr: 'killed',
        termination: ProcessTermination.timedOut,
      );
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
        timeout: const Duration(seconds: 5),
      );
      expect(result, isA<YosysRunTimeout>());
      expect((result as YosysRunTimeout).budget, const Duration(seconds: 5));
      expect(result.stderr, 'killed');
    });

    test('maps a cancelled termination to YosysRunCancelled', () async {
      final fake = _FakeRunner(
        exitCode: -9,
        termination: ProcessTermination.cancelled,
      );
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
        cancelSignal: Completer<void>().future,
      );
      expect(result, isA<YosysRunCancelled>());
    });

    test('cleans up the temp file even when the process is killed', () async {
      // A timeout-killed run still runs the finally cleanup. The fake wrote
      // a partial JSON before "being killed"; assert it is gone.
      final fake = _FakeRunner(
        exitCode: -9,
        jsonToWrite: '{"partial":',
        termination: ProcessTermination.timedOut,
      );
      final runner = YosysRunner(
        processRunner: fake,
        executable: 'yosys',
        tempDirectory: tempDir,
      );
      await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
        timeout: const Duration(seconds: 1),
      );
      final match = RegExp(
        r'write_json\s+"([^"]+)"',
      ).firstMatch(fake.capturedScript!);
      final jsonPath = match!.group(1)!;
      expect(File(jsonPath).existsSync(), isFalse);
    });
  });
}

/// A runner that fails to spawn at all — the "Yosys is not installed" case.
class _ThrowingRunner implements ProcessRunner {
  _ThrowingRunner(this.error);

  final Exception error;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async => throw error;
}

/// Records the `write_json` path of every run so a test can assert that
/// concurrent runs never share a temp file name.
class _NameCapturingRunner implements ProcessRunner {
  _NameCapturingRunner(this.names);

  final Set<String> names;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    final script = arguments[arguments.indexOf('-p') + 1];
    final path = RegExp(
      r'write_json\s+"([^"]+)"',
    ).firstMatch(script)!.group(1)!;
    names.add(path);
    // Yield so the concurrent runs genuinely interleave rather than each
    // completing before the next one allocates its name.
    await Future<void>.delayed(Duration.zero);
    File(path).writeAsStringSync('{}');
    return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}
