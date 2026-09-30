// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// A long-running command that does nothing for ~30 s, used to prove the
/// runner actually *kills* a process rather than waiting it out. If the
/// kill were broken, `run` would block for the full 30 s and the
/// surrounding `Timeout` would fail the test red — that is the mutation
/// check baked into these tests.
({String executable, List<String> arguments}) _sleeper() {
  if (Platform.isWindows) {
    // `ping -n 31 127.0.0.1` waits ~30 s (one ping per second). `timeout`
    // needs a console and refuses redirected stdin, so ping is the
    // portable long-sleep on Windows.
    return (
      executable: 'ping',
      arguments: const <String>['-n', '31', '127.0.0.1'],
    );
  }
  return (executable: '/bin/sleep', arguments: const <String>['30']);
}

({String executable, List<String> arguments}) _echo(String text) {
  if (Platform.isWindows) {
    return (executable: 'cmd', arguments: <String>['/C', 'echo', text]);
  }
  return (executable: '/bin/echo', arguments: <String>[text]);
}

void main() {
  group('DefaultProcessRunner — bounded lifecycle', () {
    const runner = DefaultProcessRunner();

    test(
      'kills a hung process after the timeout and reports timedOut',
      () async {
        final sleeper = _sleeper();
        final stopwatch = Stopwatch()..start();
        final result = await runner.run(
          sleeper.executable,
          sleeper.arguments,
          timeout: const Duration(milliseconds: 300),
        );
        stopwatch.stop();
        expect(result.termination, ProcessTermination.timedOut);
        // The process slept for 30 s; if it were not killed this would
        // not return for 30 s. Allow generous slack for CI scheduling.
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 10)),
          reason: 'a killed process must return well before its 30 s sleep',
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'kills a process when the cancelSignal fires and reports cancelled',
      () async {
        final sleeper = _sleeper();
        final cancel = Completer<void>();
        // Fire the cancel shortly after start.
        Timer(const Duration(milliseconds: 300), cancel.complete);
        final stopwatch = Stopwatch()..start();
        final result = await runner.run(
          sleeper.executable,
          sleeper.arguments,
          cancelSignal: cancel.future,
        );
        stopwatch.stop();
        expect(result.termination, ProcessTermination.cancelled);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test('a fast process exits normally even with a timeout set', () async {
      final echo = _echo('hello');
      final result = await runner.run(
        echo.executable,
        echo.arguments,
        timeout: const Duration(seconds: 30),
      );
      expect(result.termination, ProcessTermination.exited);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('hello'));
    });

    test('raises ProcessException when the binary does not exist', () {
      expect(
        () => runner.run(
          '/definitely/not/a/real/binary_xyz',
          const <String>[],
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test(
      'an errored cancelSignal does not become an unhandled error',
      () async {
        // `.listen` with no onError lets the error escalate to the zone's
        // uncaught handler, which fails an unrelated test in the same file.
        final echo = _echo('hello');
        final cancel = Completer<void>();
        Timer(
          const Duration(milliseconds: 50),
          () => cancel.completeError(StateError('caller scope died')),
        );
        final result = await runner.run(
          echo.executable,
          echo.arguments,
          cancelSignal: cancel.future,
        );
        // The run itself is unaffected: an ambiguous cancel signal must not
        // tear down a healthy process.
        expect(result.termination, ProcessTermination.exited);
        expect(result.exitCode, 0);
        // Give the zone a chance to surface an unhandled error if one leaked.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );

    group('bounded output capture', () {
      /// Emits ~[lines] lines of ~64 chars each on stdout.
      ({String executable, List<String> arguments}) chatty(int lines) {
        final payload = 'x' * 60;
        if (Platform.isWindows) {
          final script = 'for /L %i in (1,1,$lines) do @echo $payload';
          return (executable: 'cmd', arguments: <String>['/C', script]);
        }
        final script =
            'i=0; while [ \$i -lt $lines ]; do '
            'echo "$payload"; i=\$((i+1)); done';
        return (executable: '/bin/sh', arguments: <String>['-c', script]);
      }

      test(
        'caps retained stdout and flags the truncation',
        () async {
          // A verbose run on a large design previously grew the parent heap
          // to match the full output. Drain everything, retain a bound.
          const runner = DefaultProcessRunner(
            outputHeadLimit: 2000,
            outputTailLimit: 2000,
          );
          final cmd = chatty(2000); // ~122 KB, well over the 4000-char bound.
          final result = await runner.run(cmd.executable, cmd.arguments);

          expect(result.exitCode, 0);
          expect(result.stdoutTruncated, isTrue);
          expect(
            result.stdout.length,
            lessThan(6000),
            reason: 'retained output must be bounded, not the full stream',
          );
          expect(result.stdout, contains('output truncated'));
          // Head and tail are both real output, not just the marker.
          expect(result.stdout.startsWith('x'), isTrue);
          expect(result.stdout.trimRight().endsWith('x'), isTrue);
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test('short output is retained verbatim and not flagged', () async {
        const runner = DefaultProcessRunner(
          outputHeadLimit: 2000,
          outputTailLimit: 2000,
        );
        final echo = _echo('hello');
        final result = await runner.run(echo.executable, echo.arguments);
        expect(result.stdoutTruncated, isFalse);
        expect(result.stderrTruncated, isFalse);
        expect(result.stdout, contains('hello'));
        expect(result.stdout, isNot(contains('output truncated')));
      });

      test(
        'a chatty child still exits — draining stays complete',
        () async {
          // The bound must apply to *retention* only. If it stopped draining,
          // the child would wedge on a full pipe buffer and this would hang.
          const runner = DefaultProcessRunner(
            outputHeadLimit: 100,
            outputTailLimit: 100,
          );
          final cmd = chatty(5000);
          final result = await runner.run(cmd.executable, cmd.arguments);
          expect(result.termination, ProcessTermination.exited);
          expect(result.exitCode, 0);
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });

    test(
      'a killed process with a live grandchild still returns',
      () async {
        // The wrapper-script shape: we kill the shell, but the tool it
        // spawned inherits the stdout pipe and keeps running. Waiting on that
        // pipe unconditionally hangs `run` forever *after* the timeout has
        // already fired — a bounded-looking run that is not actually bounded.
        if (Platform.isWindows) return;
        const runner = DefaultProcessRunner(
          drainGrace: Duration(milliseconds: 500),
        );
        final stopwatch = Stopwatch()..start();
        final result = await runner
            .run(
              '/bin/sh',
              const <String>['-c', 'sleep 30'],
              timeout: const Duration(milliseconds: 300),
            )
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () =>
                  fail('run() hung on a pipe held by a grandchild'),
            );
        stopwatch.stop();
        expect(result.termination, ProcessTermination.timedOut);
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'the drain wait must be bounded, like the process wait',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    group('process registry', () {
      test('registers for the run and unregisters on exit', () async {
        final registry = ProcessRegistry();
        final runner = DefaultProcessRunner(registry: registry);
        final echo = _echo('hello');
        expect(registry.liveCount, 0);
        await runner.run(echo.executable, echo.arguments);
        expect(
          registry.liveCount,
          0,
          reason: 'an exited process must not stay registered',
        );
      });

      test(
        'unregisters even when the process is killed',
        () async {
          final registry = ProcessRegistry();
          final runner = DefaultProcessRunner(registry: registry);
          final sleeper = _sleeper();
          await runner.run(
            sleeper.executable,
            sleeper.arguments,
            timeout: const Duration(milliseconds: 200),
          );
          expect(registry.liveCount, 0);
        },
        timeout: const Timeout(Duration(seconds: 15)),
      );

      test('unregisters even when the spawn throws', () async {
        final registry = ProcessRegistry();
        final runner = DefaultProcessRunner(registry: registry);
        await expectLater(
          runner.run('/definitely/not/a/real/binary_xyz', const <String>[]),
          throwsA(isA<ProcessException>()),
        );
        expect(registry.liveCount, 0);
      });

      test(
        'killAll terminates a live process — the shutdown drain',
        () async {
          // The orphaned-child case: the app quits while a long tool run is
          // in flight and nothing had wired a cancelSignal.
          final registry = ProcessRegistry();
          final runner = DefaultProcessRunner(registry: registry);
          final sleeper = _sleeper();
          final pending = runner.run(sleeper.executable, sleeper.arguments);

          // Wait for the spawn to land in the registry.
          while (registry.liveCount == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(registry.liveCount, 1);

          final stopwatch = Stopwatch()..start();
          expect(registry.killAll(), 1);
          await pending;
          stopwatch.stop();

          expect(
            stopwatch.elapsed,
            lessThan(const Duration(seconds: 10)),
            reason: 'killAll must actually terminate the 30 s sleep',
          );
          expect(registry.liveCount, 0);
        },
        timeout: const Timeout(Duration(seconds: 20)),
      );

      test('killAll is safe when empty and is idempotent', () {
        final registry = ProcessRegistry();
        expect(registry.killAll(), 0);
        expect(registry.killAll(), 0);
      });
    });
  });
}
