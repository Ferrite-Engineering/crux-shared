// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// One row of the offline policy table: what a Keygen policy id grants.
///
/// A Keygen licence key carries a policy id and **no entitlements** — no tier,
/// no product codes, no email, no seat count. Policies are 1:1 with SKUs, so
/// the policy id is the only thing in a bare key that says what was bought,
/// and this table is what turns it back into a tier and a product set without
/// a network round trip.
///
/// The table is generated from the SKU catalog's `catalog_policies()` — the
/// same function that creates the policies in Keygen — and the generator
/// refuses to emit a table that disagrees with the live account. Both sides
/// deriving from one source is what stops a paying customer being silently
/// mis-tiered.
@immutable
class KeygenPolicy {
  /// Create a policy row.
  const KeygenPolicy({
    required this.id,
    required this.name,
    required this.tier,
    required this.products,
    required this.duration,
    this.stripeLookupKey,
  });

  /// Keygen policy id (a UUID) — what appears in a licence key's payload.
  final String id;

  /// Policy name, which is also the SKU name, e.g. `wavecrux-pro-monthly`.
  final String name;

  /// Tier this SKU grants.
  final LicenseTier tier;

  /// Products this SKU unlocks. A Suite SKU carries all four.
  final Set<CruxProduct> products;

  /// Policy term as configured in Keygen — 31 days monthly, 366 annual, each
  /// carrying a day of slack so renewal processing cannot race expiry.
  final Duration duration;

  /// Matching Stripe `lookup_key`, or `null` for `edu-annual`, which is free
  /// and has no Stripe counterpart.
  final String? stripeLookupKey;

  @override
  String toString() => 'KeygenPolicy($name, ${tier.name})';
}
