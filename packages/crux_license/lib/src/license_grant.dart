// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:collection/collection.dart';
import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// What a verified credential actually grants: a tier, and the products it
/// applies to.
///
/// This is the issuer-neutral answer every caller wants. `LicenseClaims` is
/// what the credential *said*; a `LicenseGrant` is what it *means* after the
/// issuer resolved it — through embedded entitlements when the credential
/// carries them, or through the compiled policy table when it does not.
@immutable
class LicenseGrant {
  /// Create a grant.
  const LicenseGrant({
    required this.issuerId,
    required this.tier,
    required this.products,
    this.licenseId,
    this.policyId,
    this.skuLookupKey,
    this.expiry,
    this.maxMachines,
    this.email,
    this.resolvedFromEntitlements = false,
  });

  /// Id of the trusted issuer whose key verified the credential.
  final String issuerId;

  /// Tier the licence grants. Never [LicenseTier.openCore] — Open Core is the
  /// absence of a licence, so it is represented by there being no grant at
  /// all, not by a grant at the bottom tier.
  final LicenseTier tier;

  /// Products this licence unlocks. A Suite SKU carries all four.
  final Set<CruxProduct> products;

  /// Issuer-side licence id, stable across renewals. What support asks for.
  final String? licenseId;

  /// Issuer-side policy id — the SKU identity inside Keygen.
  final String? policyId;

  /// SKU name, e.g. `wavecrux-pro-monthly`. Matches the Stripe `lookup_key`
  /// for every commercial SKU; `edu-annual` has no Stripe counterpart.
  final String? skuLookupKey;

  /// When the licence expires, or `null` for a perpetual licence.
  final DateTime? expiry;

  /// Seats the licence permits, when known. Enterprise seat counts are set
  /// per-licence by the Stripe bridge, so this is only present on credentials
  /// that embed the licence object.
  final int? maxMachines;

  /// Licensee email, when the credential carries one.
  final String? email;

  /// Whether [tier] and [products] came from entitlements embedded in the
  /// credential (`true`) or from the compiled policy table (`false`).
  ///
  /// Surfaced because the two have different staleness properties: embedded
  /// entitlements are as current as the credential, while the table is as
  /// current as the build.
  final bool resolvedFromEntitlements;

  /// Whether this grant covers [product].
  bool grants(CruxProduct product) => products.contains(product);

  /// Whether the licence has expired as of [now].
  ///
  /// Expiry alone does not end access: the grace period (`LicenseGracePolicy`)
  /// is decided by each product's
  /// `LicenseService`, which needs the grant in hand to decide it.
  bool isExpiredAt(DateTime now) {
    final at = expiry;
    return at != null && now.isAfter(at);
  }

  /// Time left before [expiry] as of [now]; `null` for a perpetual licence,
  /// and negative once expired.
  Duration? remainingAt(DateTime now) => expiry?.difference(now);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LicenseGrant &&
          other.issuerId == issuerId &&
          other.tier == tier &&
          const SetEquality<CruxProduct>().equals(other.products, products) &&
          other.licenseId == licenseId &&
          other.policyId == policyId &&
          other.skuLookupKey == skuLookupKey &&
          other.expiry == expiry &&
          other.maxMachines == maxMachines &&
          other.email == email &&
          other.resolvedFromEntitlements == resolvedFromEntitlements;

  @override
  int get hashCode => Object.hash(
    issuerId,
    tier,
    const SetEquality<CruxProduct>().hash(products),
    licenseId,
    policyId,
    skuLookupKey,
    expiry,
    maxMachines,
    email,
    resolvedFromEntitlements,
  );

  @override
  String toString() =>
      'LicenseGrant(${tier.name}, ${skuLookupKey ?? policyId}, '
      'products: ${products.map((p) => p.name).join(',')}, '
      'expiry: $expiry)';
}
