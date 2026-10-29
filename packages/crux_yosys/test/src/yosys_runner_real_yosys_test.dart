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

  test(
    'the formal read keeps an assertion the default read refuses',
    () async {
      final source = File('${tempDir.path}/p.v')
        ..writeAsStringSync(
          'module p(input clk, input a);\n'
          '  always @(posedge clk) assert (a == a);\n'
          'endmodule\n',
        );
      final runner = YosysRunner(tempDirectory: tempDir);
      final plain = await runner.run(
        YosysRunRequest(
          sources: [YosysSourceFile(source.path)],
          topModule: 'p',
        ),
      );
      expect(plain, isA<YosysRunFailure>());
      final formal = await runner.run(
        YosysRunRequest(
          sources: [YosysSourceFile(source.path)],
          topModule: 'p',
          frontend: YosysFrontend.verilogFormal,
        ),
      );
      expect(
        formal,
        isA<YosysRunSuccess>(),
        reason: formal is YosysRunFailure ? formal.stderr : '',
      );
      // Yosys 0.6x writes an assertion as a `$check` cell of flavour
      // `assert`; older releases as `$assert`. Either is the assertion kept.
      final json = (formal as YosysRunSuccess).rawJson;
      expect(
        json.contains(r'"type": "$assert"') ||
            json.contains('"FLAVOR": "assert"'),
        isTrue,
      );
    },
    skip: skip,
  );

  test(
    'a script reads a Liberty library before the gate-level design',
    () async {
      final lib = File('${tempDir.path}/cells.lib')
        ..writeAsStringSync('''
library (cells) {
  cell (INVX1) {
    area : 1;
    pin (A) { direction : input; }
    pin (Y) { direction : output; function : "!A"; }
  }
}
''');
      final netlist = File('${tempDir.path}/top.nl.v')
        ..writeAsStringSync(
          'module top(input a, output y);\n'
          '  INVX1 u0 (.A(a), .Y(y));\n'
          'endmodule\n',
        );
      final result = await YosysRunner(tempDirectory: tempDir).runScript(
        YosysScriptRequest(
          commands: [
            YosysScriptCommands.readLiberty(lib.path),
            YosysScriptCommands.readVerilog([netlist.path]),
            YosysScriptCommands.hierarchy('top'),
          ],
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
      final modules = json['modules']! as Map<String, Object?>;
      final cell = modules['INVX1']! as Map<String, Object?>;
      final attributes = cell['attributes']! as Map<String, Object?>;
      expect(attributes.containsKey('blackbox'), isTrue);
      final top = modules['top']! as Map<String, Object?>;
      final cells = top['cells']! as Map<String, Object?>;
      expect((cells['u0']! as Map<String, Object?>)['type'], 'INVX1');
      expect(
        tempDir.listSync().where((e) => e.path.endsWith('.json')),
        isEmpty,
      );
    },
    skip: skip,
  );

  test(
    'allowUndefinedModules keeps instances of a module no source defines',
    () async {
      final source = File('${tempDir.path}/top.v')
        ..writeAsStringSync(
          'module top(input a, output y);\n'
          '  wire n;\n'
          "  INV u1 (.A(a), .Y(n), .VDD(1'b1));\n"
          '  BUF u2 (n, y);\n'
          'endmodule\n',
        );
      final request = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile(source.path)],
        topModule: 'top',
      );
      final runner = YosysRunner(tempDirectory: tempDir);

      // By default `hierarchy -check` refuses the design.
      final checked = await runner.run(request);
      expect(checked, isA<YosysRunFailure>());
      expect(
        checked.stderr + checked.stdout,
        contains('is not part of the design'),
      );

      final result = await runner.run(
        YosysRunRequest(
          sources: request.sources,
          topModule: 'top',
          allowUndefinedModules: true,
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
      final modules = json['modules']! as Map<String, Object?>;
      expect(modules.keys, <String>['top']);
      final top = modules['top']! as Map<String, Object?>;
      final cells = top['cells']! as Map<String, Object?>;
      final u1 = cells['u1']! as Map<String, Object?>;
      final u2 = cells['u2']! as Map<String, Object?>;
      expect(u1['type'], 'INV');
      expect(u1.containsKey('port_directions'), isFalse);
      expect(
        (u1['connections']! as Map<String, Object?>).keys,
        unorderedEquals(<String>['A', 'Y', 'VDD']),
      );
      // Positional connections are numbered.
      expect(
        (u2['connections']! as Map<String, Object?>).keys,
        unorderedEquals(<String>[r'$1', r'$2']),
      );
    },
    skip: skip,
  );
}
