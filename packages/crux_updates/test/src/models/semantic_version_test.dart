// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/semantic_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemanticVersion.tryParse', () {
    test('parses a plain release', () {
      final v = SemanticVersion.tryParse('1.2.3')!;
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.preRelease, isEmpty);
      expect(v.isPreRelease, isFalse);
      expect(v.toString(), '1.2.3');
    });

    test('tolerates a leading v and surrounding whitespace', () {
      expect(
        SemanticVersion.tryParse(' v2.0.1 '),
        const SemanticVersion(2, 0, 1),
      );
    });

    test('parses pre-release identifiers and ignores build metadata', () {
      final v = SemanticVersion.tryParse('1.0.0-rc.2+build.7')!;
      expect(v.preRelease, ['rc', '2']);
      expect(v.isPreRelease, isTrue);
      expect(v.toString(), '1.0.0-rc.2');
    });

    test('returns null on malformed input', () {
      for (final bad in [
        '',
        'garbage',
        '1',
        '1.2',
        '1.2.3.4',
        'x.y.z',
        '1.2.-3',
        '1.2.3-',
      ]) {
        expect(SemanticVersion.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('ordering', () {
    test('compares core components in order', () {
      expect(
        SemanticVersion.tryParse('2.0.0')! > SemanticVersion.tryParse('1.9.9')!,
        isTrue,
      );
      expect(
        SemanticVersion.tryParse('1.3.0')! > SemanticVersion.tryParse('1.2.9')!,
        isTrue,
      );
      expect(
        SemanticVersion.tryParse('1.2.4')! > SemanticVersion.tryParse('1.2.3')!,
        isTrue,
      );
      expect(
        SemanticVersion.tryParse('1.2.3')! < SemanticVersion.tryParse('1.2.4')!,
        isTrue,
      );
    });

    test('equal versions compare equal in both directions', () {
      final a = SemanticVersion.tryParse('1.2.3')!;
      final b = SemanticVersion.tryParse('1.2.3+ignored')!;
      expect(a >= b, isTrue);
      expect(a <= b, isTrue);
      expect(a > b, isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a pre-release is older than its release', () {
      final pre = SemanticVersion.tryParse('1.0.0-beta')!;
      final rel = SemanticVersion.tryParse('1.0.0')!;
      expect(pre < rel, isTrue);
      expect(rel > pre, isTrue);
    });

    test('numeric pre-release identifiers compare numerically', () {
      expect(
        SemanticVersion.tryParse('1.0.0-rc.10')! >
            SemanticVersion.tryParse('1.0.0-rc.9')!,
        isTrue,
      );
    });

    test('numeric identifiers rank below alphanumeric ones', () {
      expect(
        SemanticVersion.tryParse('1.0.0-1')! <
            SemanticVersion.tryParse('1.0.0-alpha')!,
        isTrue,
      );
    });

    test('a longer identifier set outranks its prefix', () {
      expect(
        SemanticVersion.tryParse('1.0.0-alpha.1')! >
            SemanticVersion.tryParse('1.0.0-alpha')!,
        isTrue,
      );
    });

    test('sorts a mixed list into semver order', () {
      final versions = [
        '1.0.0',
        '1.0.0-alpha',
        '0.9.9',
        '1.0.1',
        '1.0.0-alpha.1',
      ].map((s) => SemanticVersion.tryParse(s)!).toList()..sort();
      expect(versions.map((v) => v.toString()).toList(), [
        '0.9.9',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0',
        '1.0.1',
      ]);
    });
  });
}
