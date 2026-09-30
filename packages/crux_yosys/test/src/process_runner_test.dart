// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessRunResult', () {
    test('holds exit code, stdout, and stderr as plain fields', () {
      const result = ProcessRunResult(
        exitCode: 0,
        stdout: 'hello',
        stderr: '',
      );
      expect(result.exitCode, 0);
      expect(result.stdout, 'hello');
      expect(result.stderr, '');
    });
  });

  group('DefaultProcessRunner', () {
    test('captures stdout from a real subprocess', () async {
      // Choose a tiny portable echo that exists on every supported host.
      // On POSIX systems `/bin/echo` is present; on Windows we use `cmd
      // /C echo` since `echo` is not a standalone binary there.
      const runner = DefaultProcessRunner();
      final ProcessRunResult result;
      if (Platform.isWindows) {
        result = await runner.run(
          'cmd',
          const <String>['/C', 'echo', 'hello'],
        );
      } else {
        result = await runner.run('/bin/echo', const <String>['hello']);
      }
      expect(result.exitCode, 0);
      expect(result.stdout, contains('hello'));
    });

    test(
      'streams complete stderr lines to onStderrLine as they arrive',
      () async {
        const runner = DefaultProcessRunner();
        final lines = <String>[];
        final ProcessRunResult result;
        if (Platform.isWindows) {
          result = await runner.run(
            'cmd',
            const <String>['/C', 'echo one 1>&2 && echo two 1>&2'],
            onStderrLine: lines.add,
          );
        } else {
          result = await runner.run(
            '/bin/sh',
            const <String>['-c', r'printf "one\ntwo\n" 1>&2'],
            onStderrLine: lines.add,
          );
        }
        expect(result.exitCode, 0);
        expect(lines.map((l) => l.trim()), containsAll(<String>['one', 'two']));
        // The bounded capture still holds everything — the callback is an
        // addition, not a replacement.
        expect(result.stderr, contains('one'));
        expect(result.stderr, contains('two'));
      },
    );

    test('never emits a partial line split across chunk boundaries', () async {
      // A progress parser fed "2.1. Executing HIER" matches nothing, so a
      // phase readout would flicker or never appear. Emit only complete
      // lines; the trailing partial stays buffered.
      const runner = DefaultProcessRunner();
      final lines = <String>[];
      if (Platform.isWindows) return;
      await runner.run(
        '/bin/sh',
        const <String>[
          '-c',
          r'printf "2.1. Executing HIERARCHY pass\n" 1>&2; printf "no-newline-tail" 1>&2',
        ],
        onStderrLine: lines.add,
      );
      expect(lines, contains('2.1. Executing HIERARCHY pass'));
      expect(
        lines,
        isNot(contains('no-newline-tail')),
        reason:
            'a trailing partial line must stay buffered, not be emitted '
            'as if it were complete',
      );
    });

    test('a throwing progress callback does not lose the capture', () async {
      const runner = DefaultProcessRunner();
      if (Platform.isWindows) return;
      final result = await runner.run(
        '/bin/sh',
        const <String>['-c', r'printf "a\nb\n" 1>&2'],
        onStderrLine: (_) => throw StateError('boom'),
      );
      expect(
        result.stderr,
        contains('a'),
        reason:
            'the diagnostics this run exists to capture must survive a '
            'misbehaving progress listener',
      );
    });

    test('raises ProcessException when the binary does not exist', () async {
      const runner = DefaultProcessRunner();
      expect(
        () => runner.run(
          '/definitely/not/a/real/binary_xyz',
          const <String>[],
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test(
      'stdoutFilePath streams stdout to a file verbatim, untruncated',
      () async {
        // A tiny head/tail limit would truncate the payload if it went
        // through the bounded string capture; the file path must bypass
        // that and hold the complete output.
        const runner = DefaultProcessRunner(
          outputHeadLimit: 8,
          outputTailLimit: 8,
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'crux_yosys_stdout_file_',
        );
        final outFile = File('${tempDir.path}/out.txt');
        final payload = 'X' * 4096;
        try {
          final ProcessRunResult result;
          if (Platform.isWindows) {
            result = await runner.run(
              'cmd',
              <String>['/C', 'echo', payload],
              stdoutFilePath: outFile.path,
            );
          } else {
            result = await runner.run(
              '/bin/echo',
              <String>[payload],
              stdoutFilePath: outFile.path,
            );
          }
          expect(result.exitCode, 0);
          // Nothing captured in memory; the payload went to the file.
          expect(result.stdout, isEmpty);
          expect(result.stdoutTruncated, isFalse);
          expect(outFile.existsSync(), isTrue);
          expect(outFile.readAsStringSync(), contains(payload));
        } finally {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        }
      },
    );
  });
}
