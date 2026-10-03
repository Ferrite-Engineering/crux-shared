// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// Whether a real `yosys` can be spawned on this machine.
bool _yosysOnPath() {
  try {
    return Process.runSync('yosys', <String>['-V']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final skip = _yosysOnPath() ? false : 'yosys is not on PATH';

  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crux_yosys_real_');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'include paths and defines reach a real Yosys, spaces and all',
    () async {
      // The include directory and the source both sit under a folder whose
      // name has a space. The header gives WIDTH_A; EXTRA comes from a
      // define with no default, so a define that never applied fails the
      // elaboration instead of passing silently.
      final root = Directory('${tempDir.path}/Getting Started')..createSync();
      final include = Directory('${root.path}/include files')..createSync();
      File('${include.path}/defs.vh').writeAsStringSync('`define WIDTH_A 4\n');
      final source = File('${root.path}/rtl top.v')
        ..writeAsStringSync(
          '`include "defs.vh"\n'
          'module t(output [`WIDTH_A + `EXTRA - 1:0] y);\n'
          '  assign y = 0;\n'
          'endmodule\n',
        );

      final result = await YosysRunner(tempDirectory: tempDir).run(
        YosysRunRequest(
          sources: <YosysSourceFile>[YosysSourceFile(source.path)],
          defines: const <String>['EXTRA=2'],
          includePaths: <String>[include.path],
        ),
      );

      expect(
        result,
        isA<YosysRunSuccess>(),
        reason: result is YosysRunFailure ? result.stderr : '',
      );
      final json =
          jsonDecode(
                (result as YosysRunSuccess).rawJson,
              )
              as Map<String, Object?>;
      final modules = json['modules']! as Map<String, Object?>;
      final t = modules['t']! as Map<String, Object?>;
      final ports = t['ports']! as Map<String, Object?>;
      final y = ports['y']! as Map<String, Object?>;
      expect(y['bits'], hasLength(6));
      // The per-run link directory is removed with the run.
      expect(tempDir.listSync().where((e) => e.path.endsWith('.inc')), isEmpty);
    },
    skip: skip,
  );
}
