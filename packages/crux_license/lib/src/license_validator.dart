// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/keygen_issuer.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/license_issuer.dart';
import 'package:crux_license/src/license_validation.dart';
import 'package:crux_signing/crux_signing.dart';
import 'package:meta/meta.dart';

/// Validates a signed licence credential and resolves what it grants.
///
/// ### Why the cryptography is in the open half of the repo
///
/// This package used to ship only the interface and [NoopLicenseValidator], on
/// the reasoning that "a validator whose source anyone can read alongside the
/// key material it checks is not a validator". That reasoning does not survive
/// contact with the system that was actually built: **there is no private key
/// material here to sit alongside.** Keygen generates and retains the signing
/// key and it never leaves them; what ships in a build is an account id and a
/// *public* verify key, and neither is a secret. Publishing a
/// signature-verification routine reveals nothing that verifying a signature
/// did not already reveal.
///
/// The rest of the lifecycle is here too, and is just as open. Activation
/// against Keygen, machine identity, the grace windows and the periodic
/// re-validation cadence are `KeygenLicenseClient`, `LicenseMachineIdentity`,
/// `LicenseGracePolicy` and `CruxLicenseController` in this package, written
/// once because they are exactly the decisions that must not differ between
/// products. What each Pro overlay supplies is narrow and product-specific:
/// a `LicenseStore` (the credential-store namespace), the product identity,
/// and the commerce URLs it hands the controller. None of that is secret
/// either — the closed half of the suite is the paid *features*, not the
/// licence plumbing that gates them.
///
/// ### Total, never throwing
///
/// Every method here returns a [LicenseValidation]. Users paste arbitrary text
/// into the licence panel; malformed, truncated, tampered and simply-wrong
/// input are all normal, and each one is an outcome the UI renders rather than
/// an exception it has to catch.
abstract class LicenseValidator {
  /// Human-readable identifier of this implementation, shown in About-box
  /// diagnostics to confirm which validator a build is running (`noop`,
  /// `ed25519`).
  String get name;

  /// Validate [rawCredential] on behalf of this build's product.
  ///
  /// A `null`, empty or whitespace-only credential is [LicenseAbsent] — Open
  /// Core, and not an error. [now] defaults to [DateTime.now] and exists so
  /// expiry is testable.
  ///
  /// [fingerprint] is this install's own fingerprint, the value
  /// `LicenseStore.readOrCreateFingerprint` minted. A credential bound to a
  /// machine — a machine file — resolves only when it names this fingerprint
  /// and is [LicenseRejection.wrongMachine] otherwise. That includes a call
  /// that supplies no fingerprint: a caller that does not say which install
  /// it is cannot be told a bound credential is its own, and a bound
  /// credential that resolved wherever the caller forgot to ask would be
  /// bound to nothing. Keys and licence files name no machine and are
  /// unaffected.
  Future<LicenseValidation> validate(
    String? rawCredential, {
    DateTime? now,
    String? fingerprint,
  });
}

/// Validator that grants nothing, whatever it is handed.
///
/// The default behind `licenseTierProvider`, and what tests use when they need
/// a validator that is not the point of the test. It is deliberately not
/// "accept everything": Open Core is the absence of a licence, so returning
/// [LicenseAbsent] is the honest answer.
@immutable
class NoopLicenseValidator implements LicenseValidator {
  /// Const constructor — there is no state.
  const NoopLicenseValidator();

  @override
  String get name => 'noop';

  @override
  Future<LicenseValidation> validate(
    String? rawCredential, {
    DateTime? now,
    String? fingerprint,
  }) => Future<LicenseValidation>.value(const LicenseAbsent());
}

/// The real validator: Ed25519 signature verification against a **set** of
/// trusted issuers, then resolution onto a tier and a product set.
///
/// The plural issuer set is a firm design constraint, not a generalisation for
/// its own sake. Keygen is issuer one. The second slot is reserved and empty,
/// and exists so that moving EDU to self-issued licences — a lever kept in
/// reserve because EDU is free, expected to be large, and metered — stays a
/// configuration change rather than surgery on the one component all four
/// products depend on.
///
/// Order of operations, and each step's failure is distinguishable:
///
/// 1. **Parse** the credential — licence key or licence file.
/// 2. **Verify** the signature against each trusted issuer's public key in
///    turn. Nothing verified means [LicenseRejection.untrustedIssuer], which
///    covers a tampered payload, a tampered signature and a key minted by
///    somebody else alike — they are cryptographically the same event.
/// 3. **Read** the payload into claims, and check the issuer account.
/// 4. **Resolve** claims onto a grant: embedded entitlements when the
///    credential carries them, the compiled policy table when it does not.
/// 5. **Entitle** — does the grant cover [product]?
/// 6. **Bind** — a credential that names a machine must name this one.
/// 7. **Date** — expired grants come back as [LicenseExpired] *with* the
///    grant, because grace is the caller's decision and it needs the grant to
///    make it.
class CruxLicenseValidator implements LicenseValidator {
  /// Create a validator for [product] over an explicit set of [issuers].
  CruxLicenseValidator({
    required this.product,
    required Iterable<LicenseIssuer> issuers,
  }) : issuers = List<LicenseIssuer>.unmodifiable(issuers);

  /// Create the production validator for [product]: Keygen, and nothing else.
  factory CruxLicenseValidator.production({required CruxProduct product}) =>
      CruxLicenseValidator(
        product: product,
        issuers: <LicenseIssuer>[KeygenLicenseIssuer.production()],
      );

  /// The product this build is, and therefore the entitlement it looks for.
  final CruxProduct product;

  /// Trusted issuers, tried in order.
  final List<LicenseIssuer> issuers;

  @override
  String get name => 'ed25519';

  @override
  Future<LicenseValidation> validate(
    String? rawCredential, {
    DateTime? now,
    String? fingerprint,
  }) async {
    if (rawCredential == null || rawCredential.trim().isEmpty) {
      return const LicenseAbsent();
    }

    final parse = parseLicenseCredential(rawCredential);
    final envelope = parse.envelope;
    if (envelope == null) {
      return LicenseRejected(parse.rejection!, parse.detail);
    }

    final issuer = _issuerFor(envelope);
    if (issuer == null) {
      return const LicenseRejected(
        LicenseRejection.untrustedIssuer,
        'no trusted issuer verified this credential',
      );
    }

    final claims = issuer.claimsFrom(envelope);
    if (claims == null) {
      return LicenseRejected(
        LicenseRejection.undecodablePayload,
        'issuer ${issuer.id} does not recognise this payload shape',
      );
    }
    final expected = issuer.accountId;
    if (expected != null && claims.accountId != expected) {
      return LicenseRejected(
        LicenseRejection.wrongAccount,
        'credential names account ${claims.accountId ?? '(none)'}',
      );
    }

    final grant = issuer.grantFrom(claims);
    if (grant == null) {
      return LicenseRejected(
        LicenseRejection.unknownPolicy,
        'policy ${claims.policyId ?? '(none)'} is not in this build',
      );
    }
    if (!grant.grants(product)) {
      return LicenseRejected(
        LicenseRejection.productNotEntitled,
        'grant covers ${grant.products.map((p) => p.name).join(',')}, '
        'not ${product.name}',
      );
    }
    final bound = claims.fingerprint;
    if (bound != null && bound != fingerprint) {
      return LicenseRejected(
        LicenseRejection.wrongMachine,
        fingerprint == null
            ? 'credential is bound to a machine and no fingerprint was '
                  'supplied'
            : 'credential is bound to another machine',
      );
    }

    return grant.isExpiredAt(now ?? DateTime.now())
        ? LicenseExpired(grant)
        : LicenseAccepted(grant);
  }

  LicenseIssuer? _issuerFor(LicenseEnvelope envelope) {
    for (final issuer in issuers) {
      if (ed25519Verify(
        message: envelope.signedMessage,
        signature: envelope.signature,
        publicKey: issuer.verifyKey,
      )) {
        return issuer;
      }
    }
    return null;
  }
}
