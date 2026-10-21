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

void main() {
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

    test('slang reads every source in one bare read_slang', () {
      expect(
        script(
          const YosysRunRequest(
            sources: [
              YosysSourceFile('/r/a.v'),
              YosysSourceFile.systemVerilog('/r/p.sv'),
            ],
            includePaths: ['/r/inc'],
            defines: ['W=4'],
            topModule: 'a',
            frontend: YosysFrontend.slang,
          ),
        ),
        'read_slang -I /r/inc -D W=4 /r/a.v /r/p.sv; '
        'hierarchy -check -top a; proc; write_json "/t/out.json"',
      );
    });

    test('slang refuses a source path with white space', () async {
      final runner = _Recorder(json: '{}');
      final result =
          await YosysRunner(
            processRunner: runner,
            tempDirectory: temp,
          ).run(
            const YosysRunRequest(
              sources: [YosysSourceFile('/r/my design/a.v')],
              frontend: YosysFrontend.slang,
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

    test('readSlang and hierarchy', () {
      expect(YosysScriptCommands.readSlang(['/a.sv']), 'read_slang /a.sv');
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
        () => YosysScriptCommands.readSlang(['/a b.sv']),
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
