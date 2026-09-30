// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseTier', () {
    test('has four values in the documented order', () {
      expect(LicenseTier.values, [
        LicenseTier.openCore,
        LicenseTier.edu,
        LicenseTier.pro,
        LicenseTier.enterprise,
      ]);
    });
  });

  group('LicenseTierFeatures.featureEquivalent', () {
    test('edu maps to pro (feature-equivalent under non-commercial terms)', () {
      expect(LicenseTier.edu.featureEquivalent, LicenseTier.pro);
    });

    test('openCore maps to itself', () {
      expect(LicenseTier.openCore.featureEquivalent, LicenseTier.openCore);
    });

    test('pro maps to itself', () {
      expect(LicenseTier.pro.featureEquivalent, LicenseTier.pro);
    });

    test('enterprise maps to itself', () {
      expect(LicenseTier.enterprise.featureEquivalent, LicenseTier.enterprise);
    });
  });

  group('LicenseTierFeatures.isEducational', () {
    test('returns true only for edu', () {
      expect(LicenseTier.openCore.isEducational, isFalse);
      expect(LicenseTier.edu.isEducational, isTrue);
      expect(LicenseTier.pro.isEducational, isFalse);
      expect(LicenseTier.enterprise.isEducational, isFalse);
    });
  });

  group('NoopLicenseValidator', () {
    test('grants nothing, whatever it is handed', () async {
      const validator = NoopLicenseValidator();
      expect(await validator.validate(null), isA<LicenseAbsent>());
      expect(await validator.validate(''), isA<LicenseAbsent>());
      expect(await validator.validate('key/abc.def'), isA<LicenseAbsent>());
    });

    test('resolves to openCore, which is the absence of a licence', () async {
      const validator = NoopLicenseValidator();
      final result = await validator.validate('key/abc.def');
      expect(result.tier, LicenseTier.openCore);
      expect(result.grant, isNull);
    });
  });
}
