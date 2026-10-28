// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// Records every spawn. A spawn with a stdout file is `ghdl`; it writes
/// [ghdlVerilog] there. Any other is Yosys; it writes [json] to the script's
/// `write_json` target when given.
class _Recorder implements ProcessRunner {
  _Recorder({
    this.exitCode = 0,
    this.json,
    this.termination = ProcessTermination.exited,
    this.ghdlExitCode = 0,
    this.ghdlVerilog = 'module e(); endmodule\n',
    this.ghdlTermination = ProcessTermination.exited,
    this.ghdlStderr = '',
  });

  final int exitCode;
  final String? json;
  final ProcessTermination termination;
  final int ghdlExitCode;
  final String ghdlVerilog;
  final ProcessTermination ghdlTermination;
  final String ghdlStderr;

  final List<String> executables = [];
  String? script;
  List<String>? ghdlArgs;
  String? ghdlOutput;
  String? slangCommandPath;
  String? slangCommandFile;

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
    executables.add(executable);
    if (stdoutFilePath != null) {
      ghdlArgs = arguments;
      ghdlOutput = stdoutFilePath;
      File(stdoutFilePath).writeAsStringSync(ghdlVerilog);
      return ProcessRunResult(
        exitCode: ghdlExitCode,
        stdout: '',
        stderr: ghdlStderr,
        termination: ghdlTermination,
      );
    }
    script = arguments[arguments.indexOf('-p') + 1];
    final slang = RegExp(r'read_slang -f (\S+);').firstMatch(script!);
    if (slang != null) {
      slangCommandPath = slang.group(1);
      slangCommandFile = File(slang.group(1)!).readAsStringSync();
    }
    final body = json;
    if (body != null) {
      final target = RegExp('write_json "([^"]+)"').firstMatch(script!)!;
      File(target.group(1)!).writeAsStringSync(body);
    }
    return ProcessRunResult(
      exitCode: exitCode,
      stdout: '',
      stderr: exitCode == 0 ? '' : 'ERROR: something',
      termination: termination,
    );
  }
}

class _Missing implements ProcessRunner {
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
  }) => throw ProcessException(executable, arguments, 'not found', 2);
}

/// Answers every spawn with [exitCode] (or throws when [missing]) and counts
/// the spawns, for the slang probe.
class _ProbeRunner implements ProcessRunner {
  _ProbeRunner({
    this.exitCode = 0,
    this.missing = false,
    this.stdout =
        "-- Running command `help read_slang' --\n\n"
        '    read_slang [options] [filename]\n',
  });

  final int exitCode;
  final bool missing;
  final String stdout;
  final List<List<String>> calls = [];

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
    calls.add([executable, ...arguments]);
    if (missing) throw ProcessException(executable, arguments, 'nope', 2);
    return ProcessRunResult(exitCode: exitCode, stdout: stdout, stderr: '');
  }
}

void main() {
  group('YosysAvailabilityService.probeSlang', () {
    setUp(YosysAvailabilityService.resetSlangProbeCacheForTesting);

    test(
      'asks for help on read_slang; its usage line means available',
      () async {
        final runner = _ProbeRunner();
        final service = YosysAvailabilityService(
          runner: runner,
          executableNameOverride: '/oss/bin/yosys',
        );
        expect(await service.probeSlang(), isTrue);
        expect(runner.calls.single, [
          '/oss/bin/yosys',
          '-Q',
          '-T',
          '-p',
          'help read_slang',
        ]);
      },
    );

    test('exit 0 is not enough: Homebrew Yosys answers "No such command" '
        'and exits 0', () async {
      expect(
        await YosysAvailabilityService(
          runner: _ProbeRunner(
            stdout:
                "-- Running command `help read_slang' --\n"
                'No such command or cell type: read_slang\n',
          ),
          executableNameOverride: '/brew/bin/yosys',
        ).probeSlang(),
        isFalse,
      );
    });

    test('a Yosys without the command, or no Yosys, is not', () async {
      expect(
        await YosysAvailabilityService(
          runner: _ProbeRunner(exitCode: 1),
          executableNameOverride: '/brew/bin/yosys',
        ).probeSlang(),
        isFalse,
      );
      expect(
        await YosysAvailabilityService(
          runner: _ProbeRunner(missing: true),
          executableNameOverride: '/none/yosys',
        ).probeSlang(),
        isFalse,
      );
    });

    test('the answer is cached per executable path', () async {
      final runner = _ProbeRunner();
      final a = YosysAvailabilityService(
        runner: runner,
        executableNameOverride: '/a/yosys',
      );
      await a.probeSlang();
      await a.probeSlang();
      await YosysAvailabilityService(
        runner: runner,
        executableNameOverride: '/a/yosys',
      ).probeSlang();
      expect(runner.calls, hasLength(1));
      await YosysAvailabilityService(
        runner: runner,
        executableNameOverride: '/b/yosys',
      ).probeSlang();
      expect(runner.calls, hasLength(2));
    });
  });

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('crux_yosys_fe_'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('frontend in the fixed script', () {
    String script(YosysRunRequest request) =>
        YosysRunner.buildScript(request, jsonOutputPath: '/t/out.json');

    test('verilog is the default and reads as before', () {
      const request = YosysRunRequest(
        sources: [YosysSourceFile('/r/a.v')],
        topModule: 'a',
      );
      expect(request.frontend, YosysFrontend.verilog);
      expect(
        script(request),
        'read_verilog "/r/a.v"; hierarchy -check -top a; proc; '
        'write_json "/t/out.json"',
      );
    });

    test('verilogFormal adds -formal to both dialects', () {
      expect(
        script(
          const YosysRunRequest(
            sources: [
              YosysSourceFile('/r/a.v'),
              YosysSourceFile.systemVerilog('/r/p.sv'),
            ],
            defines: ['FORMAL'],
            topModule: 'a',
            frontend: YosysFrontend.verilogFormal,
          ),
        ),
        'read_verilog -formal -D FORMAL "/r/a.v"; '
        'read_verilog -formal -sv -D FORMAL "/r/p.sv"; '
        'hierarchy -check -top a; proc; write_json "/t/out.json"',
      );
    });

    test('slang reads one command file', () {
      const request = YosysRunRequest(
        sources: [YosysSourceFile('/r/a.v')],
        topModule: 'a',
        frontend: YosysFrontend.slang,
      );
      expect(
        YosysRunner.buildScript(
          request,
          jsonOutputPath: '/t/out.json',
          slangCommandFile: '/t/read.f',
        ),
        'read_slang -f /t/read.f; hierarchy -check -top a; proc; '
        'write_json "/t/out.json"',
      );
      expect(() => script(request), throwsArgumentError);
      expect(YosysRunner.readSourcePaths(request), ['/r/a.v']);
    });

    test('a slang run writes single-unit, top, options, -I, -D and quoted '
        'sources into a command file in its temp directory, then removes '
        'it', () async {
      final runner = _Recorder(json: '{"modules": {}}');
      final result =
          await YosysRunner(
            processRunner: runner,
            tempDirectory: temp,
          ).run(
            const YosysRunRequest(
              sources: [
                YosysSourceFile('/r/my design/a.v'),
                YosysSourceFile.systemVerilog('/r/p.sv'),
              ],
              includePaths: ['/r/inc dir'],
              defines: ['W=4'],
              topModule: 'a',
              frontend: YosysFrontend.slang,
              slangOptions: ['--ignore-initial', '--ignore-assertions'],
            ),
          );
      expect(result, isA<YosysRunSuccess>());
      expect(runner.slangCommandPath, startsWith(temp.path));
      expect(runner.slangCommandFile, '''
--single-unit
--top a
--ignore-initial
--ignore-assertions
-I "/r/inc dir"
-D W=4
"/r/my design/a.v"
"/r/p.sv"
''');
      expect(File(runner.slangCommandPath!).existsSync(), isFalse);
      expect(temp.listSync(), isEmpty);
    });

    group('top-level parameter overrides', () {
      test('the built-in reader takes them as hierarchy -chparam', () {
        expect(
          script(
            const YosysRunRequest(
              sources: [YosysSourceFile.systemVerilog('/r/top.sv')],
              topModule: 'top',
              parameters: {'EN_WAIT4REGS': '1', 'W': "8'hff"},
            ),
          ),
          'read_verilog -sv "/r/top.sv"; '
          "hierarchy -check -top top -chparam EN_WAIT4REGS 1 -chparam W 8'hff; "
          'proc; write_json "/t/out.json"',
        );
      });

      test('yosys-slang takes them as -G in its command file', () async {
        expect(
          YosysScriptCommands.slangCommandFile(
            ['/r/top.sv'],
            top: 'top',
            parameters: const {'EN_WAIT4REGS': '1'},
          ),
          '--single-unit\n--top top\n-G EN_WAIT4REGS=1\n"/r/top.sv"\n',
        );
        // Not also on the hierarchy line: slang elaborated with them.
        expect(
          YosysRunner.buildScript(
            const YosysRunRequest(
              sources: [YosysSourceFile('/r/top.sv')],
              topModule: 'top',
              frontend: YosysFrontend.slang,
              parameters: {'EN_WAIT4REGS': '1'},
            ),
            jsonOutputPath: '/t/out.json',
            slangCommandFile: '/t/read.f',
          ),
          isNot(contains('-chparam')),
        );
        final runner = _Recorder(json: '{"modules": {}}');
        await YosysRunner(processRunner: runner, tempDirectory: temp).run(
          const YosysRunRequest(
            sources: [YosysSourceFile.systemVerilog('/r/top.sv')],
            topModule: 'top',
            frontend: YosysFrontend.slang,
            parameters: {'EN_WAIT4REGS': '1'},
          ),
        );
        expect(runner.slangCommandFile, contains('-G EN_WAIT4REGS=1\n'));
      });

      test('the built-in reader refuses them without a top module', () {
        expect(
          () => script(
            const YosysRunRequest(
              sources: [YosysSourceFile('/r/top.v')],
              parameters: {'W': '4'},
            ),
          ),
          throwsArgumentError,
        );
      });

      test('a value that is not one plain token is refused unrun', () async {
        for (final bad in ['', '"str"', '1 2', '1;quit', 'a\nb']) {
          final runner = _Recorder(json: '{}');
          final result =
              await YosysRunner(
                processRunner: runner,
                tempDirectory: temp,
              ).run(
                YosysRunRequest(
                  sources: const [YosysSourceFile('/r/top.v')],
                  topModule: 'top',
                  parameters: {'W': bad},
                ),
              );
          expect(
            result,
            isA<YosysRunFailure>().having(
              (f) => f.kind,
              'kind',
              YosysFailureKind.invalidRequest,
            ),
            reason: bad,
          );
          expect(runner.executables, isEmpty, reason: bad);
        }
      });

      test('are part of a request’s identity', () {
        const a = YosysRunRequest(
          sources: [YosysSourceFile('/r/top.v')],
          topModule: 'top',
          parameters: {'W': '4'},
        );
        const b = YosysRunRequest(
          sources: [YosysSourceFile('/r/top.v')],
          topModule: 'top',
          parameters: {'W': '8'},
        );
        expect(a, isNot(b));
        expect(a.copyWith(), a);
        expect(a.copyWith().hashCode, a.hashCode);
      });

      test('a name that is not an identifier is refused', () {
        expect(
          () => script(
            const YosysRunRequest(
              sources: [YosysSourceFile('/r/top.v')],
              topModule: 'top',
              parameters: {'W; quit': '4'},
            ),
          ),
          throwsArgumentError,
        );
      });

      test('they survive VHDL lowering, as do the slang options', () async {
        final runner = _Recorder(json: '{"modules": {}}');
        await YosysRunner(processRunner: runner, tempDirectory: temp).run(
          const YosysRunRequest(
            sources: [
              YosysSourceFile.systemVerilog('/r/top.sv'),
              YosysSourceFile.vhdl('/r/e.vhd'),
            ],
            topModule: 'top',
            frontend: YosysFrontend.slang,
            slangOptions: ['--ignore-assertions'],
            parameters: {'W': '4'},
          ),
        );
        expect(runner.slangCommandFile, contains('--ignore-assertions\n'));
        expect(runner.slangCommandFile, contains('-G W=4\n'));
      });
    });

    test('no top, no --top; single-unit always', () {
      expect(
        YosysScriptCommands.slangCommandFile(['/r/a.sv']),
        '--single-unit\n"/r/a.sv"\n',
      );
    });

    test('a slang option outside the allow-list is refused unrun', () async {
      for (final bad in [
        '--allow-hierarchical-const',
        '--ignore-initial --top x',
        '--blackboxed-module a;b',
        '-D X=1',
        '',
      ]) {
        final runner = _Recorder(json: '{}');
        final result =
            await YosysRunner(
              processRunner: runner,
              tempDirectory: temp,
            ).run(
              YosysRunRequest(
                sources: const [YosysSourceFile('/r/a.sv')],
                frontend: YosysFrontend.slang,
                slangOptions: [bad],
              ),
            );
        expect(
          result,
          isA<YosysRunFailure>().having(
            (f) => f.kind,
            'kind',
            YosysFailureKind.invalidRequest,
          ),
          reason: bad,
        );
        expect(runner.executables, isEmpty, reason: bad);
      }
    });

    test('slang options under another frontend are refused', () async {
      final runner = _Recorder(json: '{}');
      final result =
          await YosysRunner(
            processRunner: runner,
            tempDirectory: temp,
          ).run(
            const YosysRunRequest(
              sources: [YosysSourceFile('/r/a.sv')],
              frontend: YosysFrontend.verilogFormal,
              slangOptions: ['--ignore-initial'],
            ),
          );
      expect(
        result,
        isA<YosysRunFailure>().having(
          (f) => f.kind,
          'kind',
          YosysFailureKind.invalidRequest,
        ),
      );
      expect(runner.executables, isEmpty);
    });

    test('every allow-listed option is accepted', () {
      for (final ok in [
        '--ignore-initial',
        '--ignore-assertions',
        '--compat vcs',
        '--blackboxed-module rglts_pdm_3p3v',
        r'--blackboxed-module a$b',
      ]) {
        expect(() => YosysScriptCommands.checkSlangOption(ok), returnsNormally);
      }
    });

    test('slang options are part of a request’s identity', () {
      const a = YosysRunRequest(
        sources: [YosysSourceFile('/r/a.v')],
        frontend: YosysFrontend.slang,
      );
      const b = YosysRunRequest(
        sources: [YosysSourceFile('/r/a.v')],
        frontend: YosysFrontend.slang,
        slangOptions: ['--ignore-initial'],
      );
      expect(a == b, isFalse);
      expect(a.copyWith().slangOptions, isEmpty);
      expect(b.copyWith().slangOptions, ['--ignore-initial']);
    });

    test('the frontend survives VHDL lowering', () async {
      final runner = _Recorder(json: '{"modules": {}}');
      final result =
          await YosysRunner(
            processRunner: runner,
            tempDirectory: temp,
            ghdlExecutable: 'ghdl',
          ).run(
            const YosysRunRequest(
              sources: [
                YosysSourceFile('/r/a.sv'),
                YosysSourceFile.vhdl('/r/e.vhd'),
              ],
              vhdlTopUnit: 'e',
              frontend: YosysFrontend.verilogFormal,
            ),
          );
      expect(result, isA<YosysRunSuccess>());
      expect(runner.script, startsWith('read_verilog -formal "/r/a.sv" "'));
      expect(runner.script, contains('.v"; hierarchy -check -auto-top'));
      // The lowered temp file is gone with the run.
      expect(File(runner.ghdlOutput!).existsSync(), isFalse);
    });

    test('the frontend is part of a request’s identity', () {
      const a = YosysRunRequest(sources: [YosysSourceFile('/r/a.v')]);
      const b = YosysRunRequest(
        sources: [YosysSourceFile('/r/a.v')],
        frontend: YosysFrontend.slang,
      );
      expect(a == b, isFalse);
      expect(
        a,
        const YosysRunRequest(
          sources: [YosysSourceFile('/r/a.v')],
          // Spelled out on purpose: the default must equal the explicit value.
          // ignore: avoid_redundant_argument_values
          frontend: YosysFrontend.verilog,
        ),
      );
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('copyWith keeps the frontend', () {
      const a = YosysRunRequest(
        sources: [YosysSourceFile('/r/a.v')],
        frontend: YosysFrontend.slang,
      );
      final b = a.copyWith(includePaths: const ['/i']);
      expect(b.frontend, YosysFrontend.slang);
      expect(b.includePaths, ['/i']);
      expect(b.sources, a.sources);
    });
  });

  group('YosysScriptCommands', () {
    test('readLiberty reads a black-box library by default', () {
      expect(
        YosysScriptCommands.readLiberty('/pdk/cells lib/tt.lib'),
        'read_liberty -lib "/pdk/cells lib/tt.lib"',
      );
      expect(
        YosysScriptCommands.readLiberty('/pdk/tt.lib', lib: false),
        'read_liberty "/pdk/tt.lib"',
      );
    });

    test('readVerilog quotes files and keeps options bare', () {
      expect(
        YosysScriptCommands.readVerilog(
          ['/run/final/nl/top.nl.v'],
          includePaths: ['/inc'],
          defines: ['A=1'],
        ),
        'read_verilog -I /inc -D A=1 "/run/final/nl/top.nl.v"',
      );
      expect(
        YosysScriptCommands.readVerilog(
          ['/a.sv'],
          systemVerilog: true,
          formal: true,
        ),
        'read_verilog -formal -sv "/a.sv"',
      );
    });

    test('readSlangCommandFile and hierarchy', () {
      expect(
        YosysScriptCommands.readSlangCommandFile('/t/read.f'),
        'read_slang -f /t/read.f',
      );
      expect(YosysScriptCommands.hierarchy('top'), 'hierarchy -check -top top');
    });

    test('unsafe values throw', () {
      expect(
        () => YosysScriptCommands.readLiberty('/a";shell rm.lib'),
        throwsArgumentError,
      );
      expect(
        () => YosysScriptCommands.readVerilog(['/a.v'], defines: ['A B']),
        throwsArgumentError,
      );
      expect(
        () => YosysScriptCommands.readSlangCommandFile('/t b/read.f'),
        throwsArgumentError,
      );
      expect(
        () => YosysScriptCommands.slangCommandFile(['/a".sv']),
        throwsArgumentError,
      );
      expect(
        () => YosysScriptCommands.slangCommandFile(['/a.sv'], top: 'a b'),
        throwsArgumentError,
      );
      expect(
        () => YosysScriptCommands.slangCommandFile(
          ['/a.sv'],
          defines: ['A B'],
        ),
        throwsArgumentError,
      );
      expect(
        () => YosysScriptCommands.hierarchy('top; shell'),
        throwsArgumentError,
      );
    });
  });

  group('runScript', () {
    final request = YosysScriptRequest(
      commands: [
        YosysScriptCommands.readLiberty('/pdk/tt.lib'),
        YosysScriptCommands.readVerilog(['/run/nl.v']),
        YosysScriptCommands.hierarchy('top'),
      ],
    );

    test(
      'runs the statements, then write_json, and returns the document',
      () async {
        final runner = _Recorder(json: '{"modules": {}}');
        final result = await YosysRunner(
          processRunner: runner,
          tempDirectory: temp,
        ).runScript(request);
        expect(
          result,
          isA<YosysRunSuccess>().having(
            (s) => s.rawJson,
            'json',
            contains('modules'),
          ),
        );
        expect(
          runner.script,
          startsWith(
            'read_liberty -lib "/pdk/tt.lib"; read_verilog "/run/nl.v"; '
            'hierarchy -check -top top; write_json "',
          ),
        );
        expect(runner.script, isNot(contains('proc')));
        expect(temp.listSync(), isEmpty, reason: 'the temp JSON is removed');
      },
    );

    test('buildCallerScript is the script runScript passes', () {
      expect(
        YosysRunner.buildCallerScript(
          const YosysScriptRequest(commands: ['read_verilog "/a.v"', 'stat']),
          jsonOutputPath: '/t/o.json',
        ),
        'read_verilog "/a.v"; stat; write_json "/t/o.json"',
      );
    });

    test('a statement that smuggles a second one is refused unrun', () async {
      for (final bad in [
        'stat; shell',
        'stat\nshell',
        'read_verilog "/a.v',
        '   ',
      ]) {
        final runner = _Recorder(json: '{}');
        final result = await YosysRunner(
          processRunner: runner,
          tempDirectory: temp,
        ).runScript(YosysScriptRequest(commands: [bad]));
        expect(
          result,
          isA<YosysRunFailure>().having(
            (f) => f.kind,
            'kind',
            YosysFailureKind.invalidRequest,
          ),
          reason: bad,
        );
        expect(runner.executables, isEmpty, reason: bad);
      }
    });

    test('a non-zero exit is a failure with the diagnostics', () async {
      final result = await YosysRunner(
        processRunner: _Recorder(exitCode: 1),
        tempDirectory: temp,
      ).runScript(request);
      expect(
        result,
        isA<YosysRunFailure>()
            .having((f) => f.kind, 'kind', YosysFailureKind.nonZeroExit)
            .having((f) => f.stderr, 'stderr', contains('ERROR')),
      );
    });

    test('a clean exit without JSON is noOutput', () async {
      final result = await YosysRunner(
        processRunner: _Recorder(),
        tempDirectory: temp,
      ).runScript(request);
      expect(
        result,
        isA<YosysRunFailure>().having(
          (f) => f.kind,
          'kind',
          YosysFailureKind.noOutput,
        ),
      );
    });

    test('a timeout and a cancellation are reported as such', () async {
      final timedOut = await YosysRunner(
        processRunner: _Recorder(termination: ProcessTermination.timedOut),
        tempDirectory: temp,
      ).runScript(request, timeout: const Duration(seconds: 3));
      expect(
        timedOut,
        isA<YosysRunTimeout>().having(
          (t) => t.budget,
          'budget',
          const Duration(seconds: 3),
        ),
      );
      final cancelled = await YosysRunner(
        processRunner: _Recorder(termination: ProcessTermination.cancelled),
        tempDirectory: temp,
      ).runScript(request);
      expect(cancelled, isA<YosysRunCancelled>());
    });

    test('a missing Yosys is a launch failure, never a throw', () async {
      final result = await YosysRunner(
        processRunner: _Missing(),
        tempDirectory: temp,
      ).runScript(request);
      expect(
        result,
        isA<YosysRunFailure>().having(
          (f) => f.kind,
          'kind',
          YosysFailureKind.launch,
        ),
      );
    });
  });

  group('lowerVhdl', () {
    const vhdl = YosysRunRequest(
      sources: [YosysSourceFile.vhdl('/r/gold.vhd')],
      vhdlTopUnit: 'gold',
      vhdlStandard: '08',
    );

    test(
      'writes the emitted Verilog to the caller’s file and keeps it',
      () async {
        final out = '${temp.path}/gold.v';
        final runner = _Recorder();
        final result = await YosysRunner(
          processRunner: runner,
          ghdlExecutable: '/opt/ghdl/bin/ghdl',
        ).lowerVhdl(vhdl, outputPath: out);
        expect(
          result,
          isA<VhdlLowerSuccess>().having((s) => s.outputPath, 'path', out),
        );
        expect(File(out).readAsStringSync(), 'module e(); endmodule\n');
        expect(runner.executables, ['/opt/ghdl/bin/ghdl']);
        expect(runner.ghdlArgs, [
          '--synth',
          '--std=08',
          '--out=verilog',
          '/r/gold.vhd',
          '-e',
          'gold',
        ]);
      },
    );

    test('a request with no VHDL is refused without spawning', () async {
      final runner = _Recorder();
      final result = await YosysRunner(processRunner: runner).lowerVhdl(
        const YosysRunRequest(sources: [YosysSourceFile('/r/a.v')]),
        outputPath: '${temp.path}/x.v',
      );
      expect(
        result,
        isA<VhdlLowerFailure>().having(
          (f) => f.kind,
          'kind',
          YosysFailureKind.invalidRequest,
        ),
      );
      expect(runner.executables, isEmpty);
    });

    test('a bad unit name is an invalid request', () async {
      final result = await YosysRunner(processRunner: _Recorder()).lowerVhdl(
        const YosysRunRequest(
          sources: [YosysSourceFile.vhdl('/r/a.vhd')],
          vhdlTopUnit: 'a; rm',
        ),
        outputPath: '${temp.path}/x.v',
      );
      expect(
        result,
        isA<VhdlLowerFailure>().having(
          (f) => f.kind,
          'kind',
          YosysFailureKind.invalidRequest,
        ),
      );
    });

    test('a non-zero exit carries ghdl’s diagnostics', () async {
      final result = await YosysRunner(
        processRunner: _Recorder(
          ghdlExitCode: 1,
          ghdlStderr: 'gold.vhd:3: bad',
        ),
      ).lowerVhdl(vhdl, outputPath: '${temp.path}/x.v');
      expect(
        result,
        isA<VhdlLowerFailure>()
            .having((f) => f.kind, 'kind', YosysFailureKind.nonZeroExit)
            .having((f) => f.exitCode, 'exit', 1)
            .having((f) => f.stderr, 'stderr', 'gold.vhd:3: bad'),
      );
    });

    test('a clean exit that emitted nothing is noOutput', () async {
      final result = await YosysRunner(
        processRunner: _Recorder(ghdlVerilog: ''),
      ).lowerVhdl(vhdl, outputPath: '${temp.path}/x.v');
      expect(
        result,
        isA<VhdlLowerFailure>().having(
          (f) => f.kind,
          'kind',
          YosysFailureKind.noOutput,
        ),
      );
    });

    test('timeout, cancellation and a missing ghdl', () async {
      final out = '${temp.path}/x.v';
      expect(
        await YosysRunner(
          processRunner: _Recorder(
            ghdlTermination: ProcessTermination.timedOut,
          ),
        ).lowerVhdl(vhdl, outputPath: out, timeout: const Duration(seconds: 2)),
        isA<VhdlLowerTimeout>().having(
          (t) => t.budget,
          'budget',
          const Duration(seconds: 2),
        ),
      );
      expect(
        await YosysRunner(
          processRunner: _Recorder(
            ghdlTermination: ProcessTermination.cancelled,
          ),
        ).lowerVhdl(vhdl, outputPath: out),
        isA<VhdlLowerCancelled>(),
      );
      expect(
        await YosysRunner(
          processRunner: _Missing(),
        ).lowerVhdl(vhdl, outputPath: out),
        isA<VhdlLowerFailure>()
            .having((f) => f.kind, 'kind', YosysFailureKind.launch)
            .having((f) => f.stderr, 'stderr', contains('ghdl')),
      );
    });

    test('run() reports a ghdl failure exactly as lowerVhdl does', () async {
      final result = await YosysRunner(
        processRunner: _Recorder(ghdlExitCode: 2, ghdlStderr: 'boom'),
        tempDirectory: temp,
      ).run(vhdl);
      expect(
        result,
        isA<YosysRunFailure>()
            .having((f) => f.kind, 'kind', YosysFailureKind.nonZeroExit)
            .having((f) => f.exitCode, 'exit', 2)
            .having((f) => f.stderr, 'stderr', 'boom'),
      );
      expect(temp.listSync(), isEmpty, reason: 'the temp Verilog is removed');
    });
  });
}
