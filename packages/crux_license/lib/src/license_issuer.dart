// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_claims.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/license_grant.dart';

/// One trusted signer of licences: a public key, plus the knowledge of how to
/// read what it signs.
///
/// **The validator takes a *set* of these, and that is a firm design
/// constraint**. Today the set has exactly
/// one member, Keygen. The second slot is reserved and deliberately empty: EDU
/// is the only tier expected to be large, it is free, and Keygen bills on
/// active licensed users, so moving EDU to self-issued licences is a live
/// option. Building the plural form now costs almost nothing; retrofitting it
/// later is surgery on the one component all four products depend on.
///
/// An issuer answers three questions, in order, and the validator drives them:
///
/// 1. *Is this signature yours?* — the validator checks [verifyKey] itself, so
///    every issuer gets the same Ed25519 implementation rather than its own.
/// 2. *What does the payload say?* — [claimsFrom].
/// 3. *What does that grant?* — [grantFrom].
///
/// Splitting 2 from 3 is what lets a second issuer carry a completely
/// different claim shape while producing the same `LicenseGrant` vocabulary.
abstract class LicenseIssuer {
  /// Stable identifier, e.g. `keygen`. Appears in diagnostics and on the
  /// resulting grant.
  String get id;

  /// The 32-byte Ed25519 public key this issuer signs with.
  List<int> get verifyKey;

  /// The issuer-side account id this build trusts, or `null` if the issuer has
  /// no account concept.
  ///
  /// Checked *after* the signature: a payload from the right algorithm but the
  /// wrong account is a distinct, reportable state.
  String? get accountId;

  /// Read a verified [envelope] into issuer-neutral claims, or `null` if the
  /// payload is not a shape this issuer understands.
  LicenseClaims? claimsFrom(LicenseEnvelope envelope);

  /// Resolve [claims] onto a grant, or `null` when nothing in this build can
  /// say what the credential grants.
  LicenseGrant? grantFrom(LicenseClaims claims);
}
