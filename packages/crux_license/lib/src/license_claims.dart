// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The entitlement code that marks a licence as an evaluation.
///
/// An evaluation is an ordinary Pro or Enterprise licence that also carries
/// this code. Entitlements travel inside the signed credential, so the marker
/// cannot be removed without breaking the signature. An evaluation gets no
/// grace period (`LicenseGracePolicy`) and its expiry is checked against a
/// clock high-water mark (`LicenseClockMark`), because its end date is the
/// agreement and nothing is being renewed.
const String kEvaluationEntitlementCode = 'EVALUATION';

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
    this.issued,
    this.expiry,
    this.expiryUnreadable = false,
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

  /// When this credential was issued: the signing time of a licence file or
  /// machine file, and the licence's creation time for a key, which is signed
  /// once and carries no other.
  ///
  /// The earliest time the credential can have been in anyone's hands, which
  /// is what makes it the floor of an evaluation's clock check.
  final DateTime? issued;

  /// When the licence expires. `null` means perpetual, which no current SKU
  /// issues.
  final DateTime? expiry;

  /// Whether the payload carries an expiry that is not a date this build
  /// can read: present, but of another type, in another format, or with a
  /// year outside 1970 to 9999. [expiry] is `null` then too, and must not be
  /// read as perpetual.
  ///
  /// The validator refuses such a credential (fails closed). Only the
  /// issuer can produce one, so the realistic cause is a change or a bug on
  /// the issuer's side, and the two ways to be wrong are not symmetric:
  /// reading it as perpetual would silently give every affected licence for
  /// ever, with nothing to notice it by, while refusing it is loud, reaches
  /// support on the first day, and is fixed by a build or a reissue.
  final bool expiryUnreadable;

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
  /// Empty for a bare Keygen licence key as Keygen issues it by default: that
  /// dataset carries no entitlements at all, which is the whole reason the
  /// offline policy table exists. A key whose signed dataset does list
  /// entitlements populates this the same way a file does. A Keygen
  /// *licence file* or *machine file* embeds the full licence object and
  /// populates this, and when the codes name a tier and a product they win
  /// over the table.
  final Set<String> entitlementCodes;

  /// Whether the credential carries [kEvaluationEntitlementCode].
  bool get isEvaluation =>
      entitlementCodes.contains(kEvaluationEntitlementCode);

  /// The decoded payload, for diagnostics and for claims no field models yet.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      'LicenseClaims($issuerId, policy: $policyId, expiry: $expiry, '
      'entitlements: ${entitlementCodes.length})';
}
