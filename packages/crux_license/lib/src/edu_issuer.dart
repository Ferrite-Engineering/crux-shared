// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/keygen_policy.dart';
import 'package:crux_license/src/keygen_policy_table.dart';
import 'package:crux_license/src/license_claims.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/license_grant.dart';
import 'package:crux_license/src/license_issuer.dart';
import 'package:crux_license/src/license_time.dart';
import 'package:meta/meta.dart';

/// The `id` of every [EduLicenseIssuer], and so the `issuerId` of every grant
/// one resolves. What the controller and the licence panel test to tell a
/// self-issued educational licence from a Keygen one.
const String kEduLicenseIssuerId = 'edu';

/// The name of the self-issued educational credential format, as the app
/// declares it to the commerce backend in an `accepts` list.
const String kEduCredentialFormat = 'edu-v1';

/// The Keygen policy whose grant a self-issued educational licence
/// reproduces.
///
/// Educational licences moved off Keygen without changing what they grant, so
/// the grant is read from this policy in the compiled table rather than
/// restated: the tier, and the products it covers, are the policy's.
const String kEduAnnualPolicyName = 'edu-annual';

/// The suite's trusted educational signing keys: key id to raw 32-byte
/// Ed25519 **public** key, base64.
///
/// Public keys, not secrets; the private halves never leave the signing
/// machine. Every key here is trusted and each is tried in turn, so a key can
/// be rotated by shipping its successor here first and signing with it later.
const Map<String, String> kEduVerifyKeys = <String, String>{
  'edu-2026-a': 'tVEILSm5n02BIG6QhLrqOvkT1Gq+rhclfChlBU3wY4Y=',
  'edu-2026-b': 'h6wz8XYdmsZkdblrY6UV5xIc+K/+4xeDpDSjDOCfojQ=',
};

/// The suite's own educational issuer: the second of the issuers
/// `CruxLicenseValidator` trusts.
///
/// Reads the `edu-v1` format ([LicenseCredentialKind.eduKey]),
/// `edu/<payload>.<signature>`, whose payload is:
///
/// ```json
/// {"v": 1, "typ": "edu", "kid": "…", "id": "<uuid>", "email": "…",
///  "products": ["wavecrux", …], "iat": "<ISO 8601>", "exp": "<ISO 8601>",
///  "src": "request" | "exchange"}
/// ```
///
/// A payload whose `v` is not 1 or whose `typ` is not `edu` is not a shape
/// this issuer understands. Unknown extra fields are ignored. `kid` is
/// informational: the validator tries every trusted key, and one instance of
/// this issuer stands for each.
///
/// The grant is the grant of Keygen's [kEduAnnualPolicyName] policy, for the
/// products the payload lists that the policy covers. Nothing about an
/// educational licence is ever presented to Keygen.
@immutable
class EduLicenseIssuer implements LicenseIssuer {
  /// Create an issuer for one trusted [verifyKey].
  ///
  /// The parameters exist for tests, which sign fixtures with a throwaway
  /// keypair. Production code wants [EduLicenseIssuer.production].
  const EduLicenseIssuer({
    required this.keyId,
    required this.verifyKey,
    this.policies = kKeygenPolicies,
  });

  /// One issuer per key in [kEduVerifyKeys].
  static List<EduLicenseIssuer> production() => <EduLicenseIssuer>[
    for (final MapEntry(:key, :value) in kEduVerifyKeys.entries)
      EduLicenseIssuer(keyId: key, verifyKey: base64.decode(value)),
  ];

  /// The id of the key this instance trusts, for diagnostics.
  final String keyId;

  @override
  String get id => kEduLicenseIssuerId;

  /// Educational licences are not minted under an issuer account.
  @override
  String? get accountId => null;

  @override
  final List<int> verifyKey;

  /// The table [kEduAnnualPolicyName] is read from.
  final Map<String, KeygenPolicy> policies;

  @override
  LicenseClaims? claimsFrom(LicenseEnvelope envelope) {
    if (envelope.kind != LicenseCredentialKind.eduKey) return null;
    final payload = envelope.payload;
    if (payload['v'] != 1 || payload['typ'] != 'edu') return null;
    final licenseId = _string(payload['id']);
    if (licenseId == null) return null;
    final issued = switch (readLicenseTime(payload['iat'])) {
      LicenseTimeValue(:final at) => at,
      _ => null,
    };
    if (issued == null) return null;
    final expiry = readLicenseTime(payload['exp']);
    return LicenseClaims(
      issuerId: id,
      licenseId: licenseId,
      created: issued,
      issued: issued,
      notBefore: issued,
      expiry: switch (expiry) {
        LicenseTimeValue(:final at) => at,
        _ => null,
      },
      // Every educational licence has a term. One without a readable expiry
      // is refused, never read as perpetual.
      expiryUnreadable: expiry is! LicenseTimeValue,
      email: _string(payload['email']),
      entitlementCodes: <String>{
        if (payload['products'] case final List<Object?> products)
          for (final slug in products)
            for (final product in CruxProduct.values)
              if (product.slug == slug) product.entitlementCode,
      },
      raw: payload,
    );
  }

  @override
  LicenseGrant? grantFrom(LicenseClaims claims) {
    final policy = _eduAnnual();
    if (policy == null) return null;
    final products = <CruxProduct>{
      for (final product in policy.products)
        if (claims.entitlementCodes.contains(product.entitlementCode)) product,
    };
    if (products.isEmpty) return null;
    return LicenseGrant(
      issuerId: id,
      tier: policy.tier,
      products: products,
      licenseId: claims.licenseId,
      skuLookupKey: policy.stripeLookupKey,
      expiry: claims.expiry,
      email: claims.email,
      issued: claims.issued,
    );
  }

  KeygenPolicy? _eduAnnual() {
    for (final policy in policies.values) {
      if (policy.name == kEduAnnualPolicyName) return policy;
    }
    return null;
  }
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
