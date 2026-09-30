// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// In-memory fake runner that returns a scripted [ProcessRunResult] for
/// each invocation or throws a [ProcessException] when configured to
/// simulate a missing binary.
class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.result, this.throwsNotFound = false});

  final ProcessRunResult? result;
  final bool throwsNotFound;

  String? lastExecutable;
  List<String>? lastArguments;
  Duration? lastTimeout;

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
    lastExecutable = executable;
    lastArguments = List<String>.unmodifiable(arguments);
    lastTimeout = timeout;
    if (throwsNotFound) {
      throw ProcessException(
        executable,
        arguments,
        'No such file or directory',
        2,
      );
    }
    return result!;
  }
}

void main() {
  group('YosysAvailabilityService', () {
    test(
      'reports available when yosys -V succeeds with a Yosys banner',
      () async {
        final runner = _FakeRunner(
          result: const ProcessRunResult(
            exitCode: 0,
            stdout: 'Yosys 0.50+1 (git sha1 abcdef, ...)\n',
            stderr: '',
          ),
        );
        final service = YosysAvailabilityService(runner: runner);

        final result = await service.probe();

        expect(result.isAvailable, isTrue);
        expect(result.versionString, contains('Yosys'));
        expect(runner.lastArguments, const <String>['-V']);
      },
    );

    test('accepts a banner emitted on stderr', () async {
      final runner = _FakeRunner(
        result: const ProcessRunResult(
          exitCode: 0,
          stdout: '',
          stderr: 'Yosys 0.45 (git ...)\n',
        ),
      );
      final service = YosysAvailabilityService(runner: runner);

      final result = await service.probe();

      expect(result.isAvailable, isTrue);
      expect(result.versionString, startsWith('Yosys 0.45'));
    });

    test('reports not_on_path when the binary is missing', () async {
      final runner = _FakeRunner(throwsNotFound: true);
      final service = YosysAvailabilityService(runner: runner);

      final result = await service.probe();

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, YosysUnavailableReason.notOnPath);
      expect(result.executablePath, isNull);
    });

    test('reports exec_failed when yosys returns a non-zero exit', () async {
      final runner = _FakeRunner(
        result: const ProcessRunResult(
          exitCode: 1,
          stdout: '',
          stderr: 'failed to load library',
        ),
      );
      final service = YosysAvailabilityService(runner: runner);

      final result = await service.probe();

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, YosysUnavailableReason.execFailed);
      expect(result.executablePath, isNotNull);
    });

    test('reports banner_unparsed when output looks unrelated', () async {
      final runner = _FakeRunner(
        result: const ProcessRunResult(
          exitCode: 0,
          stdout: 'some other program output\n',
          stderr: '',
        ),
      );
      final service = YosysAvailabilityService(runner: runner);

      final result = await service.probe();

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, YosysUnavailableReason.bannerUnparsed);
    });

    test('honors a custom executable name override', () async {
      final runner = _FakeRunner(
        result: const ProcessRunResult(
          exitCode: 0,
          stdout: 'Yosys 0.50\n',
          stderr: '',
        ),
      );
      final service = YosysAvailabilityService(
        runner: runner,
        executableNameOverride: '/opt/yosys/bin/yosys',
      );

      await service.probe();

      expect(runner.lastExecutable, '/opt/yosys/bin/yosys');
    });

    test('probe passes a bounded timeout to the runner', () async {
      // Without a timeout, a yosys on a stalled network mount or a wrapper
      // script blocked on stdin hangs the probe forever with the child
      // never killed — and the probe usually runs at startup.
      final fake = _FakeRunner(
        result: const ProcessRunResult(
          exitCode: 0,
          stdout: 'Yosys 0.50',
          stderr: '',
        ),
      );
      final service = YosysAvailabilityService(
        runner: fake,
        executableNameOverride: 'yosys',
      );
      await service.probe();
      expect(
        fake.lastTimeout,
        isNotNull,
        reason: 'probe must bound the subprocess it spawns',
      );
      expect(fake.lastTimeout, YosysAvailabilityService.defaultProbeTimeout);
    });

    test('probe honours an explicit probeTimeout', () async {
      final fake = _FakeRunner(
        result: const ProcessRunResult(
          exitCode: 0,
          stdout: 'Yosys 0.50',
          stderr: '',
        ),
      );
      final service = YosysAvailabilityService(
        runner: fake,
        executableNameOverride: 'yosys',
        probeTimeout: const Duration(milliseconds: 250),
      );
      await service.probe();
      expect(fake.lastTimeout, const Duration(milliseconds: 250));
    });

    test('a timed-out probe reports unusable, not available', () async {
      // The killed process reports whatever exit status the OS gave it,
      // which can be 0 on some platforms. Branching on the exit code alone
      // would call a hung binary "available" with an unparsed banner.
      final service = YosysAvailabilityService(
        runner: _FakeRunner(
          result: const ProcessRunResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            termination: ProcessTermination.timedOut,
          ),
        ),
        executableNameOverride: 'yosys',
      );
      final availability = await service.probe();
      expect(availability.isAvailable, isFalse);
      expect(
        availability.unavailableReason,
        YosysUnavailableReason.probeTimedOut,
      );
      expect(availability.executablePath, 'yosys');
    });

    test(
      'probe never hangs when the underlying process does',
      () async {
        // End-to-end against the real DefaultProcessRunner and a real hung
        // child: a wrapper script that ignores its arguments and blocks. This
        // is the reported failure mode verbatim. Without a timeout the probe
        // future never completes and the child is never killed.
        if (Platform.isWindows) return;
        final dir = Directory.systemTemp.createTempSync('crux_yosys_hang_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final script = File('${dir.path}/yosys')
          ..writeAsStringSync('#!/bin/sh\nsleep 30\n');
        Process.runSync('chmod', <String>['+x', script.path]);
        final service = YosysAvailabilityService(
          runner: const DefaultProcessRunner(),
          executableNameOverride: script.path,
          probeTimeout: const Duration(milliseconds: 300),
        );
        final stopwatch = Stopwatch()..start();
        final availability = await service.probe().timeout(
          const Duration(seconds: 10),
        );
        stopwatch.stop();
        expect(availability.isAvailable, isFalse);
        expect(
          availability.unavailableReason,
          YosysUnavailableReason.probeTimedOut,
        );
        // Bounded by probeTimeout plus the runner's post-kill drain grace,
        // not by the script's 30 s sleep.
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
