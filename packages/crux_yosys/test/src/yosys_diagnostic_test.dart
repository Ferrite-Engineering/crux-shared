// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

void main() {
  group('YosysDiagnostic', () {
    test('equality and hashCode are value-based', () {
      const a = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.error,
        message: 'syntax error',
        filePath: 'foo.v',
        line: 3,
        column: 5,
      );
      const b = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.error,
        message: 'syntax error',
        filePath: 'foo.v',
        line: 3,
        column: 5,
      );
      const c = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.warning,
        message: 'syntax error',
        filePath: 'foo.v',
        line: 3,
        column: 5,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('toString formats file:line:column ERROR: message', () {
      const d = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.error,
        message: 'syntax error',
        filePath: 'foo.v',
        line: 3,
        column: 5,
      );
      expect(d.toString(), 'foo.v:3:5: ERROR: syntax error');
    });

    test('toString omits absent location pieces', () {
      const noCol = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.warning,
        message: 'unused port',
        filePath: 'foo.v',
        line: 3,
      );
      expect(noCol.toString(), 'foo.v:3: WARNING: unused port');
      const noFile = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.info,
        message: 'using top',
      );
      expect(noFile.toString(), 'INFO: using top');
    });

    test('copyWith replaces only specified fields', () {
      const original = YosysDiagnostic(
        severity: YosysDiagnosticSeverity.warning,
        message: 'msg',
        filePath: 'a.v',
        line: 1,
      );
      final updated = original.copyWith(
        severity: YosysDiagnosticSeverity.error,
      );
      expect(updated.severity, YosysDiagnosticSeverity.error);
      expect(updated.message, original.message);
      expect(updated.filePath, original.filePath);
    });
  });
}
