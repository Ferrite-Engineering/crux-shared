// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

void main() {
  group('YosysDiagnosticParser', () {
    const parser = YosysDiagnosticParser();

    test('parses location-prefixed ERROR with line', () {
      final result = parser.parse(
        'foo.v:3: ERROR: syntax error, unexpected token',
      );
      expect(result, hasLength(1));
      final d = result.single;
      expect(d.severity, YosysDiagnosticSeverity.error);
      expect(d.filePath, 'foo.v');
      expect(d.line, 3);
      expect(d.column, isNull);
      expect(d.message, startsWith('syntax error'));
    });

    test('parses line.column form', () {
      final result = parser.parse('foo.v:3.5: ERROR: bad thing');
      expect(result.single.line, 3);
      expect(result.single.column, 5);
    });

    test('parses line:col form (colon separator)', () {
      final result = parser.parse('a/b.v:12:7: ERROR: something');
      expect(result.single.filePath, 'a/b.v');
      expect(result.single.line, 12);
      expect(result.single.column, 7);
    });

    test('parses ranged forms (3.5-3.10 / 3:5-3:10)', () {
      final dot = parser.parse('foo.v:3.5-3.10: ERROR: ranged');
      final colon = parser.parse('foo.v:3:5-3:10: ERROR: ranged');
      expect(dot.single.line, 3);
      expect(dot.single.column, 5);
      expect(colon.single.line, 3);
      expect(colon.single.column, 5);
    });

    test('parses bare ERROR / Warning / Info lines', () {
      const lines = '''
ERROR: top-level error
Warning: deprecated cell
Info: parsing module bar
''';
      final result = parser.parse(lines);
      expect(result, hasLength(3));
      expect(result[0].severity, YosysDiagnosticSeverity.error);
      expect(result[1].severity, YosysDiagnosticSeverity.warning);
      expect(result[2].severity, YosysDiagnosticSeverity.info);
      // Bare lines have no file location.
      expect(result.every((d) => d.filePath == null), isTrue);
    });

    test('treats untagged location-prefixed messages as errors', () {
      final result = parser.parse('foo.v:5: ImplicitDefault unknown');
      expect(result.single.severity, YosysDiagnosticSeverity.error);
    });

    test('drops blank lines and free-form log noise', () {
      const input = '''
Yosys 0.50

  -- Parsing Verilog file foo.v --
foo.v:3: ERROR: bad
random log line
''';
      final result = parser.parse(input);
      // Only the ERROR line survives; the Yosys banner / progress lines
      // and indented log noise are dropped.
      expect(result, hasLength(1));
      expect(result.single.filePath, 'foo.v');
    });

    test('handles CRLF line endings', () {
      final result = parser.parse('foo.v:1: ERROR: a\r\nfoo.v:2: ERROR: b\r\n');
      expect(result, hasLength(2));
      expect(result.first.line, 1);
      expect(result.last.line, 2);
    });

    test('preserves the raw line in rawLine', () {
      final result = parser.parse('foo.v:3: ERROR: oops');
      expect(result.single.rawLine, 'foo.v:3: ERROR: oops');
    });
  });
}
