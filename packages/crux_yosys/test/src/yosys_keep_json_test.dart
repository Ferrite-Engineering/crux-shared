// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// Stands in for Yosys: finds the `write_json "<path>"` target in the `-p`
/// script and writes [json] there (nothing when null).
class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.json, this.exitCode = 0, this.sparseBytes});

  final String? json;

  /// When set, the document is a sparse file this long (no disk is used).
  final int? sparseBytes;
  final int exitCode;
  String? script;

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
    script = arguments[arguments.indexOf('-p') + 1];
    final match = RegExp(r'write_json "([^"]*)"$').firstMatch(script!);
    final target = match!.group(1)!;
    if (json != null) File(target).writeAsStringSync(json!);
    final sparse = sparseBytes;
    if (sparse != null) {
      File(target).openSync(mode: FileMode.write)
        ..truncateSync(sparse)
        ..closeSync();
    }
    return ProcessRunResult(
      exitCode: exitCode,
      stdout: 'out',
      stderr: exitCode == 0 ? '' : 'boom',
    );
  }
}

/// A test double of the kind consumers write: it overrides `run` with exactly
/// the parameters `run` has always had. That this compiles is the guard that
/// keeping the JSON stays off `run`'s signature, where a new named parameter
/// would make every such override invalid.
class _RunOverride extends YosysRunner {
  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
    Map<String, String>? environment,
  }) async => const YosysRunSuccess(rawJson: '{}', stdout: '', stderr: '');
}

/// Whether a real `yosys` can be spawned on this machine.
bool _yosysOnPath() {
  try {
    return Process.runSync('yosys', <String>['-V']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

List<File> _jsonFilesIn(Directory dir) => [
  for (final e in dir.listSync())
    if (e is File && e.path.endsWith('.json')) e,
];

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crux_yosys_keep_');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const request = YosysRunRequest(sources: [YosysSourceFile('/x/a.v')]);
  const script = YosysScriptRequest(commands: ['read_verilog "/x/a.v"']);

  group('runKeepingJson with a fake Yosys', () {
    test('the file is returned unread and left in place', () async {
      final fake = _FakeRunner(json: '{"modules": {}}');
      final result = await YosysRunner(
        processRunner: fake,
        tempDirectory: tempDir,
      ).runKeepingJson(request);
      expect(result, isA<YosysRunSuccess>());
      final success = result as YosysRunSuccess;
      expect(success.rawJson, isEmpty);
      final path = success.jsonPath!;
      expect(path.startsWith(tempDir.path), isTrue);
      expect(File(path).readAsStringSync(), '{"modules": {}}');
      expect(fake.script, endsWith('write_json "$path"'));
    });

    test('an override of run with its existing parameters stays valid', () {
      expect(_RunOverride(), isA<YosysRunner>());
    });

    test('run and runScript are unchanged: read, deleted, no path', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(json: '{}'),
        tempDirectory: tempDir,
      );
      for (final result in [
        await runner.run(request),
        await runner.runScript(script),
      ]) {
        final success = result as YosysRunSuccess;
        expect(success.rawJson, '{}');
        expect(success.jsonPath, isNull);
      }
      expect(_jsonFilesIn(tempDir), isEmpty);
    });

    test('a document too large for one string is a typed failure from run '
        'and runScript, and runKeepingJson still hands it over', () async {
      const tooBig = YosysRunner.maxInMemoryJsonBytes + 1;
      final runner = YosysRunner(
        processRunner: _FakeRunner(sparseBytes: tooBig),
        tempDirectory: tempDir,
      );
      for (final result in [
        await runner.run(request),
        await runner.runScript(script),
      ]) {
        final failure = result as YosysRunFailure;
        expect(failure.kind, YosysFailureKind.outputUnreadable);
        expect(failure.stderr, contains('$tooBig bytes'));
        expect(failure.stderr, contains('runKeepingJson'));
      }
      expect(_jsonFilesIn(tempDir), isEmpty);

      final kept = await runner.runKeepingJson(request) as YosysRunSuccess;
      expect(File(kept.jsonPath!).lengthSync(), tooBig);
      File(kept.jsonPath!).deleteSync();
    });

    test('a failed run leaves no file behind', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(json: '{}', exitCode: 1),
        tempDirectory: tempDir,
      );
      final failed = await runner.runKeepingJson(request);
      expect(failed, isA<YosysRunFailure>());
      expect(_jsonFilesIn(tempDir), isEmpty);
    });

    test('no output or an empty file is noOutput, and cleaned up', () async {
      for (final json in <String?>[null, '']) {
        final result = await YosysRunner(
          processRunner: _FakeRunner(json: json),
          tempDirectory: tempDir,
        ).runKeepingJson(request);
        expect(result, isA<YosysRunFailure>());
        expect((result as YosysRunFailure).kind, YosysFailureKind.noOutput);
      }
      expect(_jsonFilesIn(tempDir), isEmpty);
    });

    test('a file the caller deletes does not trip a later run', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(json: '{}'),
        tempDirectory: tempDir,
      );
      final first = (await runner.runKeepingJson(request)) as YosysRunSuccess;
      final second = (await runner.runKeepingJson(request)) as YosysRunSuccess;
      expect(second.jsonPath, isNot(first.jsonPath));
      File(first.jsonPath!).deleteSync();
      File(second.jsonPath!).deleteSync();
      expect(_jsonFilesIn(tempDir), isEmpty);
    });
  });

  group('runKeepingJson with a real Yosys', () {
    final skip = _yosysOnPath() ? false : 'yosys is not on PATH';

    File writeSource(Directory dir) =>
        File('${dir.path}/t.v')..writeAsStringSync(
          'module t(input a, output y);\nassign y = a;\n'
          'endmodule\n',
        );

    void expectDocument(YosysRunResult result) {
      expect(
        result,
        isA<YosysRunSuccess>(),
        reason: result is YosysRunFailure ? result.stderr : '',
      );
      final success = result as YosysRunSuccess;
      expect(success.rawJson, isEmpty);
      final json =
          jsonDecode(
                File(success.jsonPath!).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect((json['modules']! as Map<String, Object?>).containsKey('t'), true);
    }

    // One test, not three: a runner without Yosys skips every real-Yosys test,
    // and CI's skip ceiling counts each.
    test(
      'the document is kept whatever the temp directory is called',
      () async {
        final source = writeSource(tempDir);
        final spaced = Directory('${tempDir.path}/Getting Started')
          ..createSync();
        expectDocument(
          await YosysRunner(tempDirectory: spaced).runKeepingJson(
            YosysRunRequest(sources: [YosysSourceFile(source.path)]),
          ),
        );

        // Windows cannot name a directory with most of the punctuation below.
        if (Platform.isWindows) return;

        // Punctuation Yosys might read as syntax.
        const names = <String>[
          'two  spaces and a tab\there',
          'hash # mark',
          r'dollar $HOME and ${x}',
          "it's a quote",
          'back`tick',
          'amp & pipe | gt > lt <',
          'parens (a) [b] {c}',
          'star * query ? tilde ~ bang !',
          'percent %s at @ caret ^ plus + eq =',
          'comma, colon: backslash-free',
          'unicode é ü 日本',
          '--dash-first',
        ];
        for (final name in names) {
          final dir = Directory('${tempDir.path}/$name')..createSync();
          final result = await YosysRunner(tempDirectory: dir).runKeepingJson(
            YosysRunRequest(sources: [YosysSourceFile(source.path)]),
          );
          expectDocument(result);
        }

        // A double quote or semicolon is refused, with nothing left behind.
        for (final name in ['a"b', 'a;b']) {
          final dir = Directory('${tempDir.path}/$name')..createSync();
          final result = await YosysRunner(tempDirectory: dir).runKeepingJson(
            YosysRunRequest(sources: [YosysSourceFile(source.path)]),
          );
          expect(result, isA<YosysRunFailure>());
          expect(
            (result as YosysRunFailure).kind,
            YosysFailureKind.invalidRequest,
          );
          expect(_jsonFilesIn(dir), isEmpty);
        }
      },
      skip: skip,
    );
  });
}
