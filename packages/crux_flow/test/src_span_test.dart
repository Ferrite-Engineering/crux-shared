// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/src_span.dart';
import 'package:test/test.dart';

void main() {
  group('SrcSpan.tryParse: the Yosys span grammar', () {
    test('file:line.col-line.col', () {
      expect(
        SrcSpan.tryParse('path_adder.v:16.14-16.27'),
        const SrcSpan(
          file: 'path_adder.v',
          startLine: 16,
          startCol: 14,
          endLine: 16,
          endCol: 27,
        ),
      );
    });

    test('a multi-line range', () {
      expect(
        SrcSpan.tryParse('cpu.v:42.5-44.2'),
        const SrcSpan(
          file: 'cpu.v',
          startLine: 42,
          startCol: 5,
          endLine: 44,
          endCol: 2,
        ),
      );
    });

    test('the short forms older frontends write', () {
      expect(
        SrcSpan.tryParse('cpu.v:42'),
        const SrcSpan(file: 'cpu.v', startLine: 42),
      );
      expect(
        SrcSpan.tryParse('cpu.v:42.5'),
        const SrcSpan(file: 'cpu.v', startLine: 42, startCol: 5),
      );
      expect(
        SrcSpan.tryParse('cpu.v:42-44'),
        const SrcSpan(file: 'cpu.v', startLine: 42, endLine: 44),
      );
    });

    test('a relative path with directories', () {
      final span = SrcSpan.tryParse('src/cpu.v:42.5')!;
      expect(span.file, 'src/cpu.v');
      expect(span.startLine, 42);
      expect(span.startCol, 5);
    });

    test('a placeholder path as the fixtures carry it', () {
      expect(
        SrcSpan.tryParse(
          '<yosys-share>/gatemate/arith_map.v:37.23-37.25',
        )!.file,
        '<yosys-share>/gatemate/arith_map.v',
      );
    });

    test('a Windows path keeps its drive letter (last colon splits)', () {
      expect(
        SrcSpan.tryParse(r'C:\rtl\top.v:12.3-14.5'),
        const SrcSpan(
          file: r'C:\rtl\top.v',
          startLine: 12,
          startCol: 3,
          endLine: 14,
          endCol: 5,
        ),
      );
      expect(
        SrcSpan.tryParse('C:/work/rtl/top.v:7')!.file,
        'C:/work/rtl/top.v',
      );
      // A drive and no position is not a span.
      expect(SrcSpan.tryParse(r'C:\rtl\top.v'), isNull);
    });

    test('surrounding whitespace is ignored', () {
      expect(SrcSpan.tryParse('  a.v:3 '), SrcSpan.tryParse('a.v:3'));
    });

    test('malformed spans are refused, not guessed at', () {
      for (final bad in [
        '',
        'cpu.v',
        'cpu.v:',
        ':12',
        'cpu.v:abc',
        'cpu.v:0',
        'cpu.v:-3',
        'cpu.v:12.0',
        'cpu.v:12.x-13.1',
        'cpu.v:12.3-',
        'cpu.v:12.3-11.1',
        'cpu.v:12.9-12.3',
        'cpu.v:+12',
        'cpu.v:1234567890',
      ]) {
        expect(SrcSpan.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('SrcSpan.parseAll', () {
    test('returns nothing for null or empty', () {
      expect(SrcSpan.parseAll(null), isEmpty);
      expect(SrcSpan.parseAll(''), isEmpty);
    });

    test('splits a |-joined list in order, declaration first', () {
      final spans = SrcSpan.parseAll(
        'path_adder.v:16.14-16.27|<yosys-share>/gatemate/arith_map.v:37.23-37.25',
      );
      expect(spans.map((s) => s.file), [
        'path_adder.v',
        '<yosys-share>/gatemate/arith_map.v',
      ]);
      expect(
        SrcSpan.parseAll('cpu.v:42|alu.v:13').map((s) => (s.file, s.startLine)),
        [('cpu.v', 42), ('alu.v', 13)],
      );
    });

    test('drops malformed entries and keeps the rest', () {
      expect(
        SrcSpan.parseAll('cpu.v|cpu.v:abc|cpu.v:|cpu.v:99'),
        [const SrcSpan(file: 'cpu.v', startLine: 99)],
      );
    });
  });

  group('SrcSpan formatting and JSON', () {
    test('format reads back through tryParse', () {
      for (final raw in [
        'a.v:1',
        'a.v:1.2',
        'a.v:1-3',
        'a.v:1.2-3.4',
        r'C:\x\y.v:5.6-5.9',
      ]) {
        final span = SrcSpan.tryParse(raw)!;
        expect(span.format(), raw);
        expect('$span', raw);
        expect(SrcSpan.tryParse(span.format()), span);
        expect(SrcSpan.fromJson(span.toJson()), span);
        expect(SrcSpan.fromJson(span.toJson()).hashCode, span.hashCode);
      }
    });
  });

  group('matching a recorded path to the design by suffix', () {
    test('shared suffix length counts whole segments', () {
      expect(sharedPathSuffixLength('/ci/x/rtl/top.v', 'rtl/top.v'), 2);
      expect(sharedPathSuffixLength('top.v', '/home/u/p/rtl/top.v'), 1);
      expect(sharedPathSuffixLength('a/top.v', 'b/stop.v'), 0);
      expect(sharedPathSuffixLength('./rtl//top.v', 'rtl/top.v'), 2);
    });

    test('a Windows-recorded path matches a POSIX checkout', () {
      expect(
        sharedPathSuffixLength(
          r'D:\ci\proj\rtl\top.v',
          '/home/me/proj/rtl/top.v',
        ),
        3,
      );
      expect(
        matchSourceBySuffix(r'D:\ci\proj\rtl\top.v', [
          '/home/me/proj/rtl/alu.v',
          '/home/me/proj/rtl/top.v',
        ]),
        '/home/me/proj/rtl/top.v',
      );
    });

    test('the longest shared suffix wins', () {
      expect(
        matchSourceBySuffix('/ci/build/core/rtl/top.v', [
          'vendor/rtl/top.v',
          'core/rtl/top.v',
          'top.v',
        ]),
        'core/rtl/top.v',
      );
    });

    test('no shared file name is no match', () {
      expect(matchSourceBySuffix('/ci/rtl/top.v', ['rtl/alu.v']), isNull);
      expect(matchSourceBySuffix('top.v', const <String>[]), isNull);
    });

    test('a tie is refused rather than guessed', () {
      expect(
        matchSourceBySuffix('/ci/top.v', ['a/top.v', 'b/top.v']),
        isNull,
      );
      // The same candidate twice is not a tie.
      expect(
        matchSourceBySuffix('/ci/top.v', ['a/top.v', 'a/top.v']),
        'a/top.v',
      );
    });

    test('comparison is case-sensitive', () {
      expect(matchSourceBySuffix('/ci/RTL/Top.v', ['rtl/top.v']), isNull);
    });
  });
}
