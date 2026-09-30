// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The four products a licence can grant access to.
///
/// A customer holds **one** licence key however many products they bought.
/// The key names the products it unlocks
/// through Keygen entitlement codes, and each app looks for its own code
/// before reading the tier code — so the same key pasted into any of the four
/// apps either works or cleanly says "this licence is not for this product".
///
/// Open Core is the *absence* of a licence, so it has no code here.
enum CruxProduct {
  /// WaveCrux — the waveform viewer.
  waveCrux('WAVECRUX', 'WaveCrux'),

  /// NetCrux — the schematic and connectivity explorer.
  netCrux('NETCRUX', 'NetCrux'),

  /// LintCrux — the RTL lint front end.
  lintCrux('LINTCRUX', 'LintCrux'),

  /// SimCrux — the simulation runner.
  simCrux('SIMCRUX', 'SimCrux');

  const CruxProduct(this.entitlementCode, this.displayName);

  /// The Keygen entitlement code that grants this product, e.g. `WAVECRUX`.
  ///
  /// Created with the SKU catalog in Keygen; the codes are upper-case and
  /// stable, and a Suite policy carries all four.
  final String entitlementCode;

  /// Product name as written in prose and UI, e.g. `WaveCrux`.
  final String displayName;

  /// The product an entitlement [code] grants, or `null` if [code] is not a
  /// product entitlement (tier codes such as `TIER_PRO` land here).
  ///
  /// Case-insensitive, because a licence file round-trips through JSON that
  /// nothing in this package controls.
  static CruxProduct? fromEntitlementCode(String code) {
    final needle = code.toUpperCase();
    for (final product in CruxProduct.values) {
      if (product.entitlementCode == needle) return product;
    }
    return null;
  }
}
