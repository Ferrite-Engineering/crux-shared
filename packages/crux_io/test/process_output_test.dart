// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_io/src/process_output.dart';
import 'package:test/test.dart';

/// A scripted child: two line streams and an exit the test completes by hand,
/// in whatever order it wants to prove something about.
class _FakeChild {
  final StreamController<String> stdout = StreamController<String>();
  final StreamController<String> stderr = StreamController<String>();
  final Completer<int> exit = Completer<int>();

  Future<CapturedProcessOutput> collect({
    Duration drainGrace = kProcessOutputDrainGrace,
  }) => collectProcessOutput(
    stdout: stdout.stream,
    stderr: stderr.stream,
    exitCode: exit.future,
    drainGrace: drainGrace,
  );
}

void main() {
  group('collectProcessOutput', () {
    test('returns every line in order once both streams end', () async {
      final child = _FakeChild();
      final result = child.collect();
      child.stdout.add('one');
      child.stderr.add('warn');
      child.stdout.add('two');
      await child.stdout.close();
      await child.stderr.close();
      child.exit.complete(0);
      final captured = await result;
      expect(captured.exitCode, 0);
      expect(captured.stdout, ['one', 'two']);
      expect(captured.stderr, ['warn']);
    });

    test('lines that arrive after the exit are in the result', () async {
      // The shape of the false clean: the exit lands first and the only
      // line, a one-line stderr report, lands afterwards.
      final child = _FakeChild();
      final result = child.collect();
      child.exit.complete(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      child.stderr.add('top.sv:3: error: something');
      await child.stderr.close();
      await child.stdout.close();
      final captured = await result;
      expect(captured.exitCode, 1);
      expect(captured.stderr, ['top.sv:3: error: something']);
    });

    test(
      'a stream still open after the grace throws, with an excerpt',
      () async {
        final child = _FakeChild();
        final result = child.collect(
          drainGrace: const Duration(milliseconds: 50),
        );
        child.stdout.add('partial');
        child.stdout.add('   ');
        await child.stderr.close();
        child.exit.complete(0);
        await expectLater(
          result,
          throwsA(
            isA<ProcessOutputIncompleteException>()
                .having((e) => e.exitCode, 'exitCode', 0)
                .having(
                  (e) => e.loss,
                  'loss',
                  ProcessOutputLoss.streamStillOpen,
                )
                .having((e) => e.excerpt, 'excerpt', ['partial'])
                .having(
                  (e) => e.message,
                  'message',
                  'exited 0 but its output was still open 50 ms later, so the '
                      'captured output may be incomplete',
                ),
          ),
        );
        // The subscription on the pipe nobody will close is released.
        expect(child.stdout.hasListener, isFalse);
        await child.stdout.close();
      },
    );

    test('a stream that fails throws readFailed with the error', () async {
      final child = _FakeChild();
      final result = child.collect();
      child.stdout.add('before');
      child.stderr.addError(const FormatException('bad bytes'));
      await child.stdout.close();
      child.exit.complete(0);
      await expectLater(
        result,
        throwsA(
          isA<ProcessOutputIncompleteException>()
              .having((e) => e.loss, 'loss', ProcessOutputLoss.readFailed)
              .having((e) => e.readError, 'readError', isA<FormatException>())
              .having((e) => e.excerpt, 'excerpt', ['before'])
              .having(
                (e) => e.message,
                'message',
                contains('reading its output failed (FormatException: bad'),
              ),
        ),
      );
      await child.stderr.close();
    });

    test('a failed exit future releases the streams and rethrows', () async {
      final child = _FakeChild();
      final result = child.collect();
      child.exit.completeError(StateError('no process'));
      await expectLater(result, throwsStateError);
      expect(child.stdout.hasListener, isFalse);
      expect(child.stderr.hasListener, isFalse);
      await child.stdout.close();
      await child.stderr.close();
    });

    test(
      'reads a real child whose only output is one stderr line',
      () async {
        if (Platform.isWindows) return;
        final process = await Process.start('/bin/sh', <String>[
          '-c',
          'echo out; echo err >&2; exit 3',
        ]);
        final captured = await collectProcessOutput(
          stdout: process.stdout
              .transform(const SystemEncoding().decoder)
              .transform(const LineSplitter()),
          stderr: process.stderr
              .transform(const SystemEncoding().decoder)
              .transform(const LineSplitter()),
          exitCode: process.exitCode,
        );
        expect(captured.exitCode, 3);
        expect(captured.stdout, ['out']);
        expect(captured.stderr, ['err']);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('drainProcessOutput', () {
    test(
      'a caller that killed the process is not told its output is short',
      () async {
        final open = StreamController<String>();
        final drain = ProcessStreamDrain<String>(open.stream, (_) {});
        await drainProcessOutput(
          exitCode: -9,
          drains: [drain],
          drainGrace: const Duration(milliseconds: 20),
          terminatedByCaller: () => true,
        );
        expect(open.hasListener, isFalse, reason: 'released after the grace');
        await open.close();
      },
    );

    test(
      'an exited process with an open pipe throws streamStillOpen',
      () async {
        final open = StreamController<String>();
        final drain = ProcessStreamDrain<String>(open.stream, (_) {});
        await expectLater(
          drainProcessOutput(
            exitCode: 0,
            drains: [drain],
            drainGrace: const Duration(milliseconds: 20),
            terminatedByCaller: () => false,
          ),
          throwsA(
            isA<ProcessOutputIncompleteException>().having(
              (e) => e.loss,
              'loss',
              ProcessOutputLoss.streamStillOpen,
            ),
          ),
        );
        await open.close();
      },
    );

    test(
      'a drain whose onData throws is a read failure, not a crash',
      () async {
        final source = StreamController<String>();
        final drain = ProcessStreamDrain<String>(source.stream, (_) {
          throw StateError('handler bug');
        });
        source.add('x');
        await expectLater(
          drainProcessOutput(exitCode: 0, drains: [drain]),
          throwsA(
            isA<ProcessOutputIncompleteException>()
                .having((e) => e.loss, 'loss', ProcessOutputLoss.readFailed)
                .having((e) => e.readError, 'readError', isA<StateError>()),
          ),
        );
        await source.close();
      },
    );
  });

  group('ProcessStreamDrain', () {
    test('records done, error and the events it was handed', () async {
      final seen = <String>[];
      final source = StreamController<String>();
      final drain = ProcessStreamDrain<String>(source.stream, seen.add);
      expect(drain.isDone, isFalse);
      source.add('a');
      await source.close();
      await drain.done;
      expect(drain.isDone, isTrue);
      expect(drain.error, isNull);
      expect(seen, ['a']);
    });
  });

  group('ProcessOutputIncompleteException', () {
    test('formats whole seconds as seconds and the rest as milliseconds', () {
      expect(
        ProcessOutputIncompleteException.formatDrainGrace(
          const Duration(seconds: 5),
        ),
        '5 s',
      );
      expect(
        ProcessOutputIncompleteException.formatDrainGrace(
          const Duration(milliseconds: 1500),
        ),
        '1500 ms',
      );
      expect(
        ProcessOutputIncompleteException.formatDrainGrace(
          const Duration(milliseconds: 500),
        ),
        '500 ms',
      );
    });

    test('toString names the type and the message', () {
      const e = ProcessOutputIncompleteException(
        exitCode: 2,
        loss: ProcessOutputLoss.streamStillOpen,
        drainGrace: Duration(seconds: 1),
      );
      expect(
        e.toString(),
        'ProcessOutputIncompleteException: exited 2 but its output was still '
        'open 1 s later, so the captured output may be incomplete',
      );
    });
  });

  test('processOutputExcerpt keeps the first ten non-blank lines', () {
    final lines = <String>['', ' ', for (var i = 0; i < 20; i++) 'line $i'];
    final excerpt = processOutputExcerpt(lines);
    expect(excerpt, hasLength(kProcessOutputExcerptLines));
    expect(excerpt.first, 'line 0');
    expect(excerpt.last, 'line 9');
  });
}
