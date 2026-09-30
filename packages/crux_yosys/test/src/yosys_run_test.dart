// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

void main() {
  group('YosysSourceFile', () {
    test('default language is verilog', () {
      const s = YosysSourceFile('a.v');
      expect(s.language, YosysSourceLanguage.verilog);
    });

    test('named constructors set language', () {
      const v = YosysSourceFile.vhdl('a.vhd');
      const sv = YosysSourceFile.systemVerilog('a.sv');
      expect(v.language, YosysSourceLanguage.vhdl);
      expect(sv.language, YosysSourceLanguage.systemVerilog);
    });

    test('equality and hashCode are value-based', () {
      const a = YosysSourceFile('a.v');
      const b = YosysSourceFile('a.v');
      const c = YosysSourceFile.vhdl('a.v');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('YosysRunRequest', () {
    test('equality and hashCode are value-based', () {
      const a = YosysRunRequest(
        sources: <YosysSourceFile>[
          YosysSourceFile('a.v'),
          YosysSourceFile('b.v'),
        ],
        topModule: 'top',
        defines: ['FOO=1'],
        includePaths: ['inc'],
        extraCommands: ['flatten'],
      );
      const b = YosysRunRequest(
        sources: <YosysSourceFile>[
          YosysSourceFile('a.v'),
          YosysSourceFile('b.v'),
        ],
        topModule: 'top',
        defines: ['FOO=1'],
        includePaths: ['inc'],
        extraCommands: ['flatten'],
      );
      const c = YosysRunRequest(
        sources: <YosysSourceFile>[
          YosysSourceFile('a.v'),
          YosysSourceFile('b.v'),
        ],
        topModule: 'other',
        defines: ['FOO=1'],
        includePaths: ['inc'],
        extraCommands: ['flatten'],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('vhdlStandard and vhdlTopUnit participate in equality', () {
      const a = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile.vhdl('a.vhd')],
        topModule: 't',
        vhdlStandard: '08',
        vhdlTopUnit: 'unit',
      );
      const b = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile.vhdl('a.vhd')],
        topModule: 't',
        vhdlStandard: '08',
        vhdlTopUnit: 'unit',
      );
      const c = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile.vhdl('a.vhd')],
        topModule: 't',
        vhdlStandard: '08',
        vhdlTopUnit: 'different',
      );
      const d = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile.vhdl('a.vhd')],
        topModule: 't',
        vhdlStandard: '93',
        vhdlTopUnit: 'unit',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('defaults are empty lists / null top module / null vhdl knobs', () {
      const request = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile('a.v')],
      );
      expect(request.topModule, isNull);
      expect(request.defines, isEmpty);
      expect(request.includePaths, isEmpty);
      expect(request.extraCommands, isEmpty);
      expect(request.vhdlStandard, isNull);
      expect(request.vhdlTopUnit, isNull);
    });

    test('fromPaths constructor produces Verilog sources', () {
      final request = YosysRunRequest.fromPaths(
        sourceFiles: const ['a.v', 'b.v'],
        topModule: 'top',
      );
      expect(request.sources, hasLength(2));
      expect(
        request.sources.every(
          (s) => s.language == YosysSourceLanguage.verilog,
        ),
        isTrue,
      );
      expect(request.topModule, 'top');
    });

    test('hasVhdlSources / hasVerilogSources reflect the source set', () {
      const verilogOnly = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile('a.v')],
      );
      const vhdlOnly = YosysRunRequest(
        sources: <YosysSourceFile>[YosysSourceFile.vhdl('a.vhd')],
      );
      const mixed = YosysRunRequest(
        sources: <YosysSourceFile>[
          YosysSourceFile('a.v'),
          YosysSourceFile.vhdl('a.vhd'),
        ],
      );
      expect(verilogOnly.hasVerilogSources, isTrue);
      expect(verilogOnly.hasVhdlSources, isFalse);
      expect(vhdlOnly.hasVhdlSources, isTrue);
      expect(vhdlOnly.hasVerilogSources, isFalse);
      expect(mixed.hasVerilogSources, isTrue);
      expect(mixed.hasVhdlSources, isTrue);
    });

    test('sourcePaths flattens the typed list', () {
      const request = YosysRunRequest(
        sources: <YosysSourceFile>[
          YosysSourceFile('a.v'),
          YosysSourceFile.vhdl('b.vhd'),
        ],
      );
      expect(request.sourcePaths, ['a.v', 'b.vhd']);
    });
  });

  group('YosysRunResult', () {
    test('YosysRunSuccess carries rawJson and captured streams', () {
      const result = YosysRunSuccess(
        rawJson: '{"creator": "Yosys"}',
        stdout: 'log line',
        stderr: '',
      );
      expect(result.rawJson, contains('Yosys'));
      expect(result.stdout, 'log line');
    });

    test('YosysRunFailure carries the exit code', () {
      const result = YosysRunFailure(
        exitCode: 1,
        stdout: '',
        stderr: 'error',
      );
      expect(result.exitCode, 1);
      expect(result.stderr, 'error');
    });

    group('YosysRunFailure.kind', () {
      test('an explicit kind wins over the exit code', () {
        // The runner reports three different failures with exit code -1.
        const invalid = YosysRunFailure(
          kind: YosysFailureKind.invalidRequest,
          exitCode: -1,
          stdout: '',
          stderr: 'Invalid Yosys request: bad path',
        );
        expect(invalid.kind, YosysFailureKind.invalidRequest);
        expect(invalid.exitCode, -1);
      });

      test('without one, it is derived from the exit code', () {
        // A failure built before the field existed, or by a test double,
        // keeps meaning what its exit code meant.
        YosysFailureKind derived(int exitCode) =>
            YosysRunFailure(exitCode: exitCode, stdout: '', stderr: '').kind;

        expect(derived(-1), YosysFailureKind.launch);
        expect(derived(0), YosysFailureKind.noOutput);
        expect(derived(1), YosysFailureKind.nonZeroExit);
        expect(derived(137), YosysFailureKind.nonZeroExit);
      });

      test('the derivation keys on the runner launch exit code', () {
        // The model mirrors the runner's constant rather than importing it;
        // this keeps the two from drifting apart.
        expect(
          const YosysRunFailure(
            exitCode: YosysRunner.launchFailureExitCode,
            stdout: '',
            stderr: '',
          ).kind,
          YosysFailureKind.launch,
        );
      });

      test('an exhaustive switch over the result type still compiles', () {
        // The discriminator is a field, not a new subtype, so a consumer's
        // existing exhaustive switch over YosysRunResult keeps compiling.
        const YosysRunResult result = YosysRunFailure(
          kind: YosysFailureKind.launch,
          exitCode: -1,
          stdout: '',
          stderr: 'Could not run the executable "yosys": No such file',
        );
        final tag = switch (result) {
          YosysRunFailure(kind: YosysFailureKind.launch) => 'not installed',
          YosysRunFailure() => 'failure',
          YosysRunSuccess() => 'success',
          YosysRunTimeout() => 'timeout',
          YosysRunCancelled() => 'cancelled',
        };
        expect(tag, 'not installed');
      });
    });

    test('sealed types switch exhaustively', () {
      const YosysRunResult result = YosysRunSuccess(
        rawJson: '{}',
        stdout: '',
        stderr: '',
      );
      final tag = switch (result) {
        YosysRunSuccess() => 'success',
        YosysRunFailure() => 'failure',
        YosysRunTimeout() => 'timeout',
        YosysRunCancelled() => 'cancelled',
      };
      expect(tag, 'success');
    });
  });
}
