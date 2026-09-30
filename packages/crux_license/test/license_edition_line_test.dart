// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line the macOS application menu states above `About <Product>`.
///
/// The case that drives the design is an Enterprise seat licensed from a policy
/// file: it has no user email BY CONSTRUCTION, so the obvious implementation
/// renders an empty string or the word "null" into a menu nobody can dismiss.
void main() {
  const strings = CruxEditionLineStringsEn();

  CruxLicenseStatus statusFor(LicenseTier tier, {String? email}) =>
      CruxLicenseStatus(
        activation: tier == LicenseTier.openCore
            ? CruxLicenseActivation.openCore
            : CruxLicenseActivation.active,
        grant: tier == LicenseTier.openCore
            ? null
            : LicenseGrant(
                issuerId: 'keygen',
                tier: tier,
                products: const {CruxProduct.waveCrux},
                email: email,
              ),
      );

  group('there is nothing to say at Open Core', () {
    test('returns null rather than naming an edition', () {
      // A menu item reading "Open Core edition" would be chrome advertising the
      // absence of a purchase.
      expect(
        cruxLicenseEditionLine(statusFor(LicenseTier.openCore), strings),
        isNull,
      );
    });
  });

  group('a licence that names somebody', () {
    test('states the edition and the identity', () {
      expect(
        cruxLicenseEditionLine(
          statusFor(LicenseTier.pro, email: 'buyer@example.com'),
          strings,
        ),
        'Pro edition — buyer@example.com',
      );
    });

    test('each edition uses its own name', () {
      expect(
        cruxLicenseEditionLine(
          statusFor(LicenseTier.edu, email: 'student@uni.edu'),
          strings,
        ),
        startsWith('Educational edition'),
      );
      expect(
        cruxLicenseEditionLine(
          statusFor(LicenseTier.enterprise, email: 'it@example.com'),
          strings,
        ),
        startsWith('Enterprise edition'),
      );
    });
  });

  group('a licence that names nobody', () {
    // THE case this function exists for. An Enterprise seat licensed by policy
    // file has no user email, and that is normal rather than an error.
    test('says the organization licensed it', () {
      expect(
        cruxLicenseEditionLine(statusFor(LicenseTier.enterprise), strings),
        'Enterprise edition — licensed by your organization',
      );
    });

    test('an empty email is treated as absent, not rendered', () {
      final line = cruxLicenseEditionLine(
        statusFor(LicenseTier.pro, email: '   '),
        strings,
      );
      expect(line, 'Pro edition — licensed by your organization');
      expect(line, isNot(contains('null')));
      expect(line!.trim(), isNot(endsWith('—')));
    });

    test('no tier ever renders the word null or a dangling dash', () {
      for (final tier in LicenseTier.values) {
        for (final email in <String?>[null, '', '  ']) {
          final line = cruxLicenseEditionLine(
            statusFor(tier, email: email),
            strings,
          );
          if (line == null) continue;
          expect(line, isNot(contains('null')), reason: '$tier / "$email"');
          expect(line.trim(), isNot(endsWith('—')), reason: '$tier / "$email"');
          expect(line.trim(), isNotEmpty, reason: '$tier / "$email"');
        }
      }
    });
  });
}
