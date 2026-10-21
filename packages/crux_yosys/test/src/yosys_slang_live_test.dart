// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

/// The Yosys to test the slang frontend with: `CRUX_SLANG_YOSYS` when set
/// (point it at an OSS CAD Suite `bin/yosys`), otherwise `yosys` on `PATH`.
final String _yosys = Platform.environment['CRUX_SLANG_YOSYS'] ?? 'yosys';

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_yosys_slang_');
    YosysAvailabilityService.resetSlangProbeCacheForTesting();
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  // One test, so a machine without yosys-slang adds one skip, not several.
  test(
    'a real yosys-slang reads a multi-file design through the command file',
    () async {
      final available = await YosysAvailabilityService(
        executableNameOverride: _yosys,
      ).probeSlang();
      if (!available) {
        markTestSkipped('$_yosys has no read_slang (set CRUX_SLANG_YOSYS)');
        return;
      }
      // A directory with a space; a macro defined in one file and used in
      // the next (needs --single-unit); a define from the request; an
      // include directory with a space.
      final root = Directory('${temp.path}/rtl dir')..createSync();
      final inc = Directory('${root.path}/inc dir')..createSync();
      File('${inc.path}/w.svh').writeAsStringSync('`define W 3\n');
      final defs = File('${root.path}/defs.sv')
        ..writeAsStringSync('`include "w.svh"\n');
      final top = File('${root.path}/top.sv')
        ..writeAsStringSync(
          'module top(input logic clk, output logic [`W + `EXTRA - 1:0] q);\n'
          '  always_ff @(posedge clk) q <= q + 1;\n'
          'endmodule\n',
        );
      final work = Directory('${temp.path}/work')..createSync();
      final result =
          await YosysRunner(
            executable: _yosys,
            tempDirectory: work,
          ).run(
            YosysRunRequest(
              sources: [
                YosysSourceFile.systemVerilog(defs.path),
                YosysSourceFile.systemVerilog(top.path),
              ],
              topModule: 'top',
              includePaths: [inc.path],
              defines: const ['EXTRA=2'],
              frontend: YosysFrontend.slang,
              slangOptions: const ['--ignore-initial', '--ignore-assertions'],
            ),
          );
      expect(
        result,
        isA<YosysRunSuccess>(),
        reason: result is YosysRunFailure ? result.stderr : '',
      );
      final json =
          jsonDecode((result as YosysRunSuccess).rawJson)
              as Map<String, Object?>;
      final module =
          (json['modules']! as Map<String, Object?>)['top']!
              as Map<String, Object?>;
      final ports = module['ports']! as Map<String, Object?>;
      expect((ports['q']! as Map<String, Object?>)['bits'], hasLength(5));
      // yosys-slang writes src relative to Yosys's working directory, never
      // as the absolute path it was given.
      final src =
          (module['attributes']! as Map<String, Object?>)['src']! as String;
      expect(src, contains('top.sv'));
      expect(src, isNot(startsWith(top.path)));
      // The command file and the JSON went with the run.
      expect(work.listSync(), isEmpty);
    },
  );
}
