// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// One spawn as the runner saw it.
class _Spawn {
  _Spawn(this.executable, this.environment);

  final String executable;
  final Map<String, String>? environment;
}

/// Records the environment of every spawn and answers like a healthy Yosys
/// or GHDL, so each path under test completes.
class _RecordingRunner implements ProcessRunner {
  final List<_Spawn> spawns = <_Spawn>[];

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
    spawns.add(_Spawn(executable, environment));
    if (stdoutFilePath != null) {
      File(stdoutFilePath).writeAsStringSync('module lowered(); endmodule\n');
    }
    final pIndex = arguments.indexOf('-p');
    if (pIndex >= 0 && arguments.length > pIndex + 1) {
      final script = arguments[pIndex + 1];
      final match = RegExp(r'write_json\s+"([^"]+)"').firstMatch(script);
      if (match != null) File(match.group(1)!).writeAsStringSync('{}');
      if (script == 'help read_slang') {
        return const ProcessRunResult(
          exitCode: 0,
          stdout: 'read_slang [options]\n',
          stderr: '',
        );
      }
    }
    return const ProcessRunResult(
      exitCode: 0,
      stdout: 'Yosys 0.50 (git sha1 abc)\n',
      stderr: '',
    );
  }
}

void main() {
  late Directory tempDir;
  late _RecordingRunner fake;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crux_yosys_env_test_');
    fake = _RecordingRunner();
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  YosysRunner runnerWith({Map<String, String>? environment}) => YosysRunner(
    processRunner: fake,
    executable: 'yosys',
    ghdlExecutable: 'ghdl',
    tempDirectory: tempDir,
    environment: environment,
  );

  const verilog = YosysRunRequest(
    sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
  );
  const vhdl = YosysRunRequest(
    sources: <YosysSourceFile>[YosysSourceFile.vhdl('/tmp/foo.vhd')],
    topModule: 'foo',
  );
  const script = YosysScriptRequest(commands: <String>['help']);
  const engineEnv = <String, String>{
    'PATH': '/opt/oss-cad-suite/bin',
    'XDG_DATA_HOME': '/tmp/job-1',
  };

  group('YosysRunner environment', () {
    test('passes no environment when none is given', () async {
      final runner = runnerWith();
      await runner.run(verilog);
      await runner.runScript(script);
      expect(fake.spawns, hasLength(2));
      expect(fake.spawns.map((s) => s.environment), everyElement(isNull));
    });

    test('run forwards the constructor environment to yosys', () async {
      final result = await runnerWith(environment: engineEnv).run(verilog);
      expect(result, isA<YosysRunSuccess>());
      expect(fake.spawns.single.executable, 'yosys');
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('run forwards the per-call environment to yosys', () async {
      await runnerWith().run(verilog, environment: engineEnv);
      expect(fake.spawns.single.environment, engineEnv);
    });

    test(
      'run reaches both the ghdl and the yosys spawn of a VHDL request',
      () async {
        final result = await runnerWith(environment: engineEnv).run(vhdl);
        expect(result, isA<YosysRunSuccess>());
        expect(fake.spawns.map((s) => s.executable), <String>['ghdl', 'yosys']);
        for (final spawn in fake.spawns) {
          expect(spawn.environment, engineEnv);
        }
      },
    );

    test('run forwards a per-call environment to ghdl as well', () async {
      await runnerWith().run(vhdl, environment: engineEnv);
      expect(fake.spawns, hasLength(2));
      for (final spawn in fake.spawns) {
        expect(spawn.environment, engineEnv);
      }
    });

    test('runScript forwards the constructor environment', () async {
      final result = await runnerWith(environment: engineEnv).runScript(script);
      expect(result, isA<YosysRunSuccess>());
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('runScript forwards the per-call environment', () async {
      await runnerWith().runScript(script, environment: engineEnv);
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('lowerVhdl forwards the constructor environment to ghdl', () async {
      final result = await runnerWith(
        environment: engineEnv,
      ).lowerVhdl(vhdl, outputPath: '${tempDir.path}/out.v');
      expect(result, isA<VhdlLowerSuccess>());
      expect(fake.spawns.single.executable, 'ghdl');
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('lowerVhdl forwards the per-call environment to ghdl', () async {
      await runnerWith().lowerVhdl(
        vhdl,
        outputPath: '${tempDir.path}/out.v',
        environment: engineEnv,
      );
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('the per-call environment wins per variable', () async {
      final runner = runnerWith(
        environment: const {'PATH': '/constructor', 'KEEP': 'yes'},
      );
      await runner.run(verilog, environment: const {'PATH': '/call'});
      await runner.runScript(script, environment: const {'PATH': '/call'});
      await runner.run(vhdl, environment: const {'PATH': '/call'});
      await runner.lowerVhdl(
        vhdl,
        outputPath: '${tempDir.path}/out.v',
        environment: const {'PATH': '/call'},
      );
      expect(fake.spawns, hasLength(5));
      for (final spawn in fake.spawns) {
        expect(spawn.environment, const {'PATH': '/call', 'KEEP': 'yes'});
      }
    });

    test(
      'a later change to the map given to the constructor is not seen',
      () async {
        final env = <String, String>{'PATH': '/first'};
        final runner = runnerWith(environment: env);
        env['PATH'] = '/second';
        await runner.run(verilog);
        expect(fake.spawns.single.environment, const {'PATH': '/first'});
      },
    );
  });

  group('YosysAvailabilityService environment', () {
    test('probe forwards the environment', () async {
      final service = YosysAvailabilityService(
        runner: fake,
        environment: engineEnv,
      );
      final availability = await service.probe();
      expect(availability.isAvailable, isTrue);
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('probeSlang forwards the environment', () async {
      final service = YosysAvailabilityService(
        runner: fake,
        executableNameOverride: 'yosys-env-test',
        environment: engineEnv,
      );
      expect(await service.probeSlang(), isTrue);
      expect(fake.spawns.single.environment, engineEnv);
    });

    test('passes no environment when none is given', () async {
      final service = YosysAvailabilityService(
        runner: fake,
        executableNameOverride: 'yosys-env-test-none',
      );
      await service.probe();
      await service.probeSlang();
      expect(fake.spawns, hasLength(2));
      expect(fake.spawns.map((s) => s.environment), everyElement(isNull));
    });
  });
}
