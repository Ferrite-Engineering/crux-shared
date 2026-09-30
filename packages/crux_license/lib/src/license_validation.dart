// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_grant.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// Why a credential was refused.
///
/// Every value is a state the UI has to be able to say something honest about,
/// which is why they are distinguished at all: "this key is for NetCrux" and
/// "this key has been tampered with" are the same rejection to a validator and
/// completely different sentences to a user.
enum LicenseRejection {
  /// The text is not a credential this build recognises — wrong prefix, no
  /// separator, not a licence file.
  malformed,

  /// The credential is shaped right but its payload is not decodable JSON.
  undecodablePayload,

  /// The credential names an algorithm this build does not implement. Keygen
  /// licence files can be AES-encrypted; those need the licence key as the
  /// decryption secret and are not accepted as a bare paste.
  unsupportedAlgorithm,

  /// No trusted issuer's public key verifies the signature. Covers a tampered
  /// payload, a tampered signature, and a key minted by somebody else.
  untrustedIssuer,

  /// The signature verifies but the credential was minted under a different
  /// issuer account than this build trusts.
  wrongAccount,

  /// The signature verifies but the policy id is not in this build's table and
  /// the credential embeds no entitlements — so nothing can say what it
  /// grants. Almost always means the build predates the SKU.
  unknownPolicy,

  /// The licence is valid and current, but grants a different product than the
  /// one asking.
  productNotEntitled,

  /// The credential is bound to a machine, and this is not it. A machine file
  /// carries the fingerprint of the install it was checked out for and
  /// resolves nowhere else; the remedy is a file issued against this
  /// install's own offline activation request.
  wrongMachine,
}

/// Outcome of validating a credential.
///
/// A sealed hierarchy rather than an exception: validation is a normal thing
/// for the UI to do with untrusted user input, and every outcome including
/// "garbage" is an outcome to render, not an error to catch. Nothing in this
/// package throws for a bad key.
@immutable
sealed class LicenseValidation {
  const LicenseValidation();

  /// The grant, when there is one — for [LicenseAccepted] and
  /// [LicenseExpired], `null` otherwise.
  LicenseGrant? get grant => null;

  /// The tier to run at on this outcome alone, ignoring any grace period.
  ///
  /// [LicenseExpired] resolves to [LicenseTier.openCore] here: grace is a
  /// per-product policy applied on top of this by `LicenseService`, not
  /// something the validator may grant on its own.
  LicenseTier get tier => LicenseTier.openCore;
}

/// No credential was supplied. This is Open Core, and it is not an error —
/// it is the state every user starts in.
@immutable
final class LicenseAbsent extends LicenseValidation {
  /// Create the absent outcome.
  const LicenseAbsent();

  @override
  String toString() => 'LicenseAbsent()';
}

/// The credential verified, resolved, and is current.
@immutable
final class LicenseAccepted extends LicenseValidation {
  /// Create an accepted outcome carrying [grant].
  const LicenseAccepted(this.grant);

  @override
  final LicenseGrant grant;

  @override
  LicenseTier get tier => grant.tier;

  @override
  String toString() => 'LicenseAccepted($grant)';
}

/// The credential verified and resolved, but its expiry has passed.
///
/// Deliberately not a [LicenseRejection]: the grant is still authentic and
/// still says what it says, and the grace machinery (`LicenseGracePolicy`)
/// needs exactly that — tier, products and
/// expiry — to decide whether to keep running. Reporting this as a rejection
/// would force every caller to re-derive the grant from the raw key.
@immutable
final class LicenseExpired extends LicenseValidation {
  /// Create an expired outcome carrying [grant].
  const LicenseExpired(this.grant);

  @override
  final LicenseGrant grant;

  @override
  String toString() => 'LicenseExpired($grant)';
}

/// The credential was refused.
@immutable
final class LicenseRejected extends LicenseValidation {
  /// Create a rejection with a machine-readable [reason] and a
  /// developer-facing [detail].
  const LicenseRejected(this.reason, [this.detail = '']);

  /// Why it was refused.
  final LicenseRejection reason;

  /// Developer-facing detail for logs and the About-box diagnostics. Never
  /// shown raw to a user — the UI maps [reason] to a localized sentence.
  final String detail;

  @override
  String toString() =>
      'LicenseRejected(${reason.name}${detail.isEmpty ? '' : ': $detail'})';
}
