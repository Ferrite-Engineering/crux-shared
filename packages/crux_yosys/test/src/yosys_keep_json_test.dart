// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// Stands in for Yosys: finds the `write_json "<path>"` target in the `-p`
/// script and writes [json] there (nothing when null).
class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.json, this.exitCode = 0});

  final String? json;
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
    return ProcessRunResult(
      exitCode: exitCode,
      stdout: 'out',
      stderr: exitCode == 0 ? '' : 'boom',
    );
  }
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

  group('keepJson with a fake Yosys', () {
    test('run: the file is returned unread and left in place', () async {
      final fake = _FakeRunner(json: '{"modules": {}}');
      final result = await YosysRunner(
        processRunner: fake,
        tempDirectory: tempDir,
      ).run(request, keepJson: true);
      expect(result, isA<YosysRunSuccess>());
      final success = result as YosysRunSuccess;
      expect(success.rawJson, isEmpty);
      final path = success.jsonPath!;
      expect(path.startsWith(tempDir.path), isTrue);
      expect(File(path).readAsStringSync(), '{"modules": {}}');
      expect(fake.script, endsWith('write_json "$path"'));
    });

    test('runScript: the file is returned unread and left in place', () async {
      final result = await YosysRunner(
        processRunner: _FakeRunner(json: '{}'),
        tempDirectory: tempDir,
      ).runScript(script, keepJson: true);
      final success = result as YosysRunSuccess;
      expect(success.rawJson, isEmpty);
      expect(File(success.jsonPath!).existsSync(), isTrue);
    });

    test('without it nothing changes: read, deleted, no path', () async {
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

    test('a failed run leaves no file behind', () async {
      final runner = YosysRunner(
        processRunner: _FakeRunner(json: '{}', exitCode: 1),
        tempDirectory: tempDir,
      );
      final failed = await runner.run(request, keepJson: true);
      expect(failed, isA<YosysRunFailure>());
      final failedScript = await runner.runScript(script, keepJson: true);
      expect(failedScript, isA<YosysRunFailure>());
      expect(_jsonFilesIn(tempDir), isEmpty);
    });

    test('no output or an empty file is noOutput, and cleaned up', () async {
      for (final json in <String?>[null, '']) {
        final result = await YosysRunner(
          processRunner: _FakeRunner(json: json),
          tempDirectory: tempDir,
        ).run(request, keepJson: true);
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
      final first =
          (await runner.run(request, keepJson: true)) as YosysRunSuccess;
      final second =
          (await runner.run(request, keepJson: true)) as YosysRunSuccess;
      expect(second.jsonPath, isNot(first.jsonPath));
      File(first.jsonPath!).deleteSync();
      File(second.jsonPath!).deleteSync();
      expect(_jsonFilesIn(tempDir), isEmpty);
    });
  });

  group('keepJson with a real Yosys', () {
    final skip = _yosysOnPath() ? false : 'yosys is not on PATH';
    // Windows cannot name a directory with most of the punctuation below.
    final skipPunctuation = Platform.isWindows
        ? 'Windows file names cannot hold this punctuation'
        : skip;

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

    test('a temp directory with spaces', () async {
      final dir = Directory('${tempDir.path}/Getting Started')..createSync();
      final runner = YosysRunner(tempDirectory: dir);
      final source = writeSource(tempDir);
      expectDocument(
        await runner.run(
          YosysRunRequest(sources: [YosysSourceFile(source.path)]),
          keepJson: true,
        ),
      );
      expectDocument(
        await runner.runScript(
          YosysScriptRequest(
            commands: [
              YosysScriptCommands.readVerilog([source.path]),
              YosysScriptCommands.hierarchy('t'),
            ],
          ),
          keepJson: true,
        ),
      );
    }, skip: skip);

    test(
      'a temp directory with punctuation Yosys might read as syntax',
      () async {
        final source = writeSource(tempDir);
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
          final result = await YosysRunner(tempDirectory: dir).run(
            YosysRunRequest(sources: [YosysSourceFile(source.path)]),
            keepJson: true,
          );
          expectDocument(result);
        }
      },
      skip: skipPunctuation,
    );

    test(
      'a temp directory holding a double quote or semicolon is refused',
      () async {
        final source = writeSource(tempDir);
        for (final name in ['a"b', 'a;b']) {
          final dir = Directory('${tempDir.path}/$name')..createSync();
          final result = await YosysRunner(tempDirectory: dir).run(
            YosysRunRequest(sources: [YosysSourceFile(source.path)]),
            keepJson: true,
          );
          expect(result, isA<YosysRunFailure>());
          expect(
            (result as YosysRunFailure).kind,
            YosysFailureKind.invalidRequest,
          );
          expect(_jsonFilesIn(dir), isEmpty);
        }
      },
      skip: skipPunctuation,
    );
  });
}
