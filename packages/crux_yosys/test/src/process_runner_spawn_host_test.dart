// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// DefaultProcessRunner resolves the engine name against an injected Windows
// host before it spawns, so the Windows branch runs on every CI machine.
//
// On Windows, CreateProcess searches the launching process's current
// directory before PATH, and a product launched from a terminal has the
// user's repository there. Two things must hold: an installed engine is
// started by the absolute path found on PATH, and an engine that is not
// installed is reported as not installed with nothing started, because a
// bare name would be searched for in that repository.
//
// A resolved path does not exist on the machine running the test, so its
// spawn fails in the OS. That failure names the path that was attempted,
// which is the assertion: the runner tried the absolute path and never the
// bare name.
//
// MUTATION: resolving with the lenient form (or not at all) turns the
// not-installed tests red, because the bare name then reaches Process.start
// and fails with the OS's own message instead of the resolver's.

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

void main() {
  const installDir = r'C:\oss-cad-suite\bin';

  SpawnHost windowsHost({Set<String> present = const <String>{}}) => SpawnHost(
    windows: true,
    environment: const <String, String>{
      'Path': r'C:\rtl-repo;' + installDir,
      'PATHEXT': '.COM;.EXE;.BAT;.CMD',
    },
    exists: present.contains,
  );

  group('DefaultProcessRunner on a Windows host', () {
    test('an engine that is not installed spawns nothing', () async {
      final registry = ProcessRegistry();
      final runner = DefaultProcessRunner(
        spawnHost: windowsHost(),
        registry: registry,
      );

      await expectLater(
        runner.run('yosys.exe', const <String>['-V']),
        throwsA(
          isA<ProcessException>()
              .having((e) => e.executable, 'executable', 'yosys.exe')
              .having((e) => e.message, 'message', 'not found on PATH')
              .having((e) => e.errorCode, 'errorCode', 2),
        ),
      );
      expect(registry.liveCount, 0);
    });

    test('an installed engine is started by its absolute path', () async {
      final runner = DefaultProcessRunner(
        spawnHost: windowsHost(present: <String>{'$installDir\\yosys.exe'}),
        registry: ProcessRegistry(),
      );

      await expectLater(
        runner.run('yosys.exe', const <String>['-V']),
        throwsA(
          isA<ProcessException>().having(
            (e) => e.executable,
            'executable',
            '$installDir\\yosys.exe',
          ),
        ),
      );
    });

    test("the child environment's PATH is searched first", () async {
      // An engine found only on the PATH the caller builds for the child
      // (an augmented one) still resolves to its absolute path.
      final runner = DefaultProcessRunner(
        spawnHost: windowsHost(present: <String>{r'C:\extra\ghdl.EXE'}),
        registry: ProcessRegistry(),
      );

      await expectLater(
        runner.run(
          'ghdl',
          const <String>['--version'],
          environment: const <String, String>{'PATH': r'C:\extra'},
        ),
        throwsA(
          isA<ProcessException>().having(
            (e) => e.executable,
            'executable',
            r'C:\extra\ghdl.EXE',
          ),
        ),
      );
    });
  });

  group('an uninstalled engine reaches the normal not-installed result', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('spawn_host_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('YosysRunner reports a launch failure', () async {
      final runner = YosysRunner(
        processRunner: DefaultProcessRunner(
          spawnHost: windowsHost(),
          registry: ProcessRegistry(),
        ),
        executable: 'yosys.exe',
        tempDirectory: tempDir,
      );

      final result = await runner.run(
        const YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile('/tmp/foo.v')],
        ),
      );

      expect(result, isA<YosysRunFailure>());
      final failure = result as YosysRunFailure;
      expect(failure.kind, YosysFailureKind.launch);
      expect(failure.stderr, contains('"yosys.exe"'));
      expect(failure.stderr, contains('not found on PATH'));
    });

    test('YosysAvailabilityService reports it as not found', () async {
      final service = YosysAvailabilityService(
        runner: DefaultProcessRunner(
          spawnHost: windowsHost(),
          registry: ProcessRegistry(),
        ),
        executableNameOverride: 'yosys.exe',
      );

      final availability = await service.probe();
      expect(availability.isAvailable, isFalse);
      expect(
        availability.unavailableReason,
        YosysUnavailableReason.notOnPath,
      );
    });
  });

  test('off Windows the name is spawned as given', () async {
    // execvp searches PATH only, never the current directory, so a POSIX
    // host passes the bare name through and the OS reports it missing.
    final runner = DefaultProcessRunner(
      spawnHost: const SpawnHost(windows: false),
      registry: ProcessRegistry(),
    );

    await expectLater(
      runner.run('crux-no-such-engine', const <String>[]),
      throwsA(
        isA<ProcessException>()
            .having((e) => e.executable, 'executable', 'crux-no-such-engine')
            .having((e) => e.message, 'message', isNot('not found on PATH')),
      ),
    );
  });
}
