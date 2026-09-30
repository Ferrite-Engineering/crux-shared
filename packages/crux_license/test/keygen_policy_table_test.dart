// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the generated policy table.
///
/// The table is the offline half of licence resolution: a Keygen licence key
/// carries a policy id and no entitlements, so if this table is wrong a paying
/// customer is silently mis-tiered and nothing anywhere reports it. The
/// generator reconciles it against the
/// live Keygen account at generation time; these are the properties that must
/// hold in the checked-in artefact, with no network.
void main() {
  group('kKeygenPolicies', () {
    test('holds the twenty commercial SKUs plus edu-annual', () {
      // 4 products x {pro, ent} x {monthly, annual} = 16, plus 4 suite SKUs,
      // plus edu-annual. The count is asserted because a partial regeneration
      // is the failure this table cannot survive.
      expect(kKeygenPolicies, hasLength(21));
      expect(
        kKeygenPolicies.values.where((p) => p.tier == LicenseTier.edu),
        hasLength(1),
      );
    });

    test('is keyed by each policy own id', () {
      for (final entry in kKeygenPolicies.entries) {
        expect(entry.value.id, entry.key);
      }
    });

    test('names are unique — they are the SKU identity', () {
      final names = kKeygenPolicies.values.map((p) => p.name).toSet();
      expect(names, hasLength(kKeygenPolicies.length));
    });

    test('every commercial SKU matches a Stripe lookup key', () {
      for (final policy in kKeygenPolicies.values) {
        if (policy.tier == LicenseTier.edu) {
          expect(
            policy.stripeLookupKey,
            isNull,
            reason: 'EDU is free and has no Stripe counterpart',
          );
        } else {
          expect(policy.stripeLookupKey, policy.name);
        }
      }
    });

    test('every product is reachable at every paid tier', () {
      for (final product in CruxProduct.values) {
        for (final tier in <LicenseTier>[
          LicenseTier.pro,
          LicenseTier.enterprise,
          LicenseTier.edu,
        ]) {
          expect(
            kKeygenPolicies.values.any(
              (p) => p.tier == tier && p.products.contains(product),
            ),
            isTrue,
            reason: 'no SKU grants ${product.name} at ${tier.name}',
          );
        }
      }
    });

    test('suite SKUs carry all four products, single SKUs carry one', () {
      for (final policy in kKeygenPolicies.values) {
        if (policy.name.startsWith('suite-') || policy.name == 'edu-annual') {
          expect(policy.products, hasLength(4), reason: policy.name);
        } else {
          expect(policy.products, hasLength(1), reason: policy.name);
        }
      }
    });

    test('durations carry the day of slack the catalog specifies', () {
      // 31 days monthly and 366 annual, so renewal processing cannot race
      // expiry.
      for (final policy in kKeygenPolicies.values) {
        final expected = policy.name.endsWith('-monthly')
            ? const Duration(days: 31)
            : const Duration(days: 366);
        expect(policy.duration, expected, reason: policy.name);
      }
    });

    test('no policy resolves to openCore', () {
      // Open Core is the absence of a licence. A SKU that granted it would be
      // a SKU that sells nothing.
      expect(
        kKeygenPolicies.values.map((p) => p.tier),
        isNot(contains(LicenseTier.openCore)),
      );
    });
  });

  group('CruxProduct', () {
    test('entitlement codes round-trip', () {
      for (final product in CruxProduct.values) {
        expect(
          CruxProduct.fromEntitlementCode(product.entitlementCode),
          product,
        );
        expect(
          CruxProduct.fromEntitlementCode(
            product.entitlementCode.toLowerCase(),
          ),
          product,
          reason: 'a licence file round-trips through JSON we do not control',
        );
      }
    });

    test('a tier code is not a product', () {
      expect(CruxProduct.fromEntitlementCode('TIER_PRO'), isNull);
      expect(CruxProduct.fromEntitlementCode(''), isNull);
    });
  });
}
