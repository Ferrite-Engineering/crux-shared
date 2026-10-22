// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:crux_io/src/signature.dart';
import 'package:test/test.dart';

import 'signature_vectors.dart';

void main() {
  group('CruxSignature.compute', () {
    test('reproduces every signature the scheme has shipped', () {
      for (final (i, (row, expected)) in shippedSignatures.indexed) {
        expect(
          CruxSignature.compute([row[0], row[1]], shippedText(i)),
          expected,
          reason: 'shipped case $i',
        );
      }
    });

    test('is the hash of the fields and normalized text joined by |', () {
      expect(
        CruxSignature.compute(['task', 'assert', 'rtl/a.sv'], '  a\n  b '),
        cruxFnv1a64('task|assert|rtl/a.sv|a b'),
      );
      expect(CruxSignature.compute(const [], 'x'), cruxFnv1a64('x'));
    });

    test('reflowing the text keeps the signature; changing it does not', () {
      final a = CruxSignature.compute(['r', 'f'], 'one two');
      expect(CruxSignature.compute(['r', 'f'], 'one\n   two\n'), a);
      expect(CruxSignature.compute(['r', 'f'], 'one three'), isNot(a));
    });

    test('names its scheme', () {
      expect(CruxSignature.scheme, 'crux-fnv1a64/1');
    });
  });

  group('cruxFnv1a64', () {
    test('known vectors of 64-bit FNV-1a over ASCII', () {
      expect(cruxFnv1a64(''), 'cbf29ce484222325');
      expect(cruxFnv1a64('a'), 'af63dc4c8601ec8c');
      expect(cruxFnv1a64('foobar'), '85944171f73967e8');
    });

    test('agrees with a BigInt oracle over the whole code-unit space', () {
      final random = Random(0xB4A5E11E);
      for (var i = 0; i < 2000; i++) {
        final input = String.fromCharCodes([
          for (var j = random.nextInt(64); j > 0; j--) random.nextInt(0x10000),
        ]);
        expect(
          cruxFnv1a64(input),
          referenceFnv1a64(input),
          reason: 'iteration $i',
        );
      }
    });

    test('is always 16 lowercase hex digits', () {
      final hex16 = RegExp(r'^[0-9a-f]{16}$');
      for (final s in ['', 'x', '\uffff' * 10, 'pad']) {
        expect(cruxFnv1a64(s), matches(hex16));
      }
    });
  });

  group('CruxSignature.normalizeText', () {
    test('collapses white-space runs and trims', () {
      expect(CruxSignature.normalizeText(' a \t\n b\u2003c '), 'a b c');
      expect(CruxSignature.normalizeText(' \n '), '');
    });
  });

  group('CruxSignature.projectRelativePath', () {
    test('a file inside a POSIX root becomes root-relative', () {
      expect(
        CruxSignature.projectRelativePath('/work/soc/rtl/a.sv', '/work/soc'),
        'rtl/a.sv',
      );
    });

    test('a Windows root is read as Windows on every host', () {
      expect(
        CruxSignature.projectRelativePath(
          r'C:\work\soc\rtl\a.sv',
          r'C:\work\soc',
        ),
        'rtl/a.sv',
      );
    });

    test('a file outside the root, or no root, is unchanged', () {
      expect(
        CruxSignature.projectRelativePath('/other/a.sv', '/work/soc'),
        '/other/a.sv',
      );
      expect(
        CruxSignature.projectRelativePath('<module:top>', ''),
        '<module:top>',
      );
    });
  });

  group('CruxSignature.projectRelativeMessage', () {
    test('removes the root prefix wherever it is quoted', () {
      expect(
        CruxSignature.projectRelativeMessage(
          'driven at /work/soc/rtl/a.sv and /work/soc/rtl/b.sv',
          '/work/soc',
        ),
        'driven at rtl/a.sv and rtl/b.sv',
      );
    });

    test('a Windows root is removed in both separator styles', () {
      expect(
        CruxSignature.projectRelativeMessage(
          r'C:\work\soc\a.sv and C:/work/soc/b.sv',
          r'C:\work\soc',
        ),
        'a.sv and b.sv',
      );
    });

    test('no root leaves the text alone', () {
      expect(CruxSignature.projectRelativeMessage('/x/y', ''), '/x/y');
    });
  });
}
