// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// What a verified credential *asserts*, in issuer-neutral form.
///
/// This is the boundary between "the bytes are authentic" and "here is what
/// they mean". A `LicenseIssuer` produces a `LicenseClaims` once the signature
/// checks out; resolving those claims onto a `LicenseGrant` — a tier and a set
/// of products — is a separate step, because the two issuers the validator is
/// designed for (Keygen, and a reserved self-issued slot) carry different claim
/// shapes and only the grant is common vocabulary.
///
/// Every field is nullable on purpose. A Keygen licence-key payload is a small
/// JSON object with no schema guarantees beyond what the account happens to
/// issue today, and a validator that throws on a missing field is a validator
/// that locks a paying customer out when Keygen adds one.
@immutable
class LicenseClaims {
  /// Create a claim set. All fields optional; [issuerId] identifies which
  /// trusted issuer's key verified the signature.
  const LicenseClaims({
    required this.issuerId,
    this.accountId,
    this.productId,
    this.policyId,
    this.policyDuration,
    this.licenseId,
    this.created,
    this.expiry,
    this.email,
    this.maxMachines,
    this.fingerprint,
    this.entitlementCodes = const <String>{},
    this.raw = const <String, Object?>{},
  });

  /// Id of the `LicenseIssuer` whose public key verified this credential.
  final String issuerId;

  /// Issuer account the credential was minted under. For Keygen this is
  /// checked against the compiled-in account id — a signature from the right
  /// algorithm but the wrong account is not ours.
  final String? accountId;

  /// Issuer-side product id. Keygen models the whole suite as one product, so
  /// this is *not* the `CruxProduct` the licence grants.
  final String? productId;

  /// Issuer-side policy id. For Keygen this is the SKU, 1:1 with a Stripe
  /// price, and the only thing in a bare licence key that identifies what was
  /// bought.
  final String? policyId;

  /// Policy term as issued, e.g. 31 days for a monthly SKU.
  final Duration? policyDuration;

  /// Issuer-side licence id — stable across renewals, and what support asks
  /// for.
  final String? licenseId;

  /// When the licence was created.
  final DateTime? created;

  /// When the licence expires. `null` means perpetual, which no current SKU
  /// issues.
  final DateTime? expiry;

  /// Licensee email, when the credential carries one. A bare Keygen licence
  /// key does not.
  final String? email;

  /// Seats (machine activations) the licence permits, when the credential
  /// carries it. A bare Keygen licence key does not.
  final int? maxMachines;

  /// The install fingerprint the credential is bound to, or `null` when it is
  /// not bound to any.
  ///
  /// A Keygen machine file is checked out against one registered machine and
  /// carries that machine's fingerprint inside the signed payload; a licence
  /// key and a licence file name no machine. A bound credential resolves only
  /// on the install whose fingerprint matches — that is the property that
  /// makes it safe to issue for a machine that will never reach the issuer.
  final String? fingerprint;

  /// Entitlement codes embedded in the credential, upper-case.
  ///
  /// Empty for a bare Keygen licence key — that format carries no entitlements
  /// at all, which is the whole reason the offline policy table exists. A
  /// Keygen *licence file* embeds the full licence object and does populate
  /// this, and when it is populated it wins over the table.
  final Set<String> entitlementCodes;

  /// The decoded payload, for diagnostics and for claims no field models yet.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      'LicenseClaims($issuerId, policy: $policyId, expiry: $expiry, '
      'entitlements: ${entitlementCodes.length})';
}
