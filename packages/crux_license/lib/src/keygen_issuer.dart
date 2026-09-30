// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/keygen_policy.dart';
import 'package:crux_license/src/keygen_policy_table.dart';
import 'package:crux_license/src/license_claims.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/license_grant.dart';
import 'package:crux_license/src/license_issuer.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// Keygen account the suite's licences are minted under.
///
/// Not a secret. It is compiled into every build precisely so a licence can be
/// verified with no network, and it appears in every Keygen API URL the client
/// calls.
const String kKeygenAccountId = '58d52938-51ab-4192-85d8-835dfd23fd93';

/// Keygen's Ed25519 **public** verify key for that account, hex-encoded.
///
/// Also not a secret, and the reason the cryptographic validator can live in
/// the open half of the repo at all: the private half is held by Keygen and
/// never leaves it.
const String kKeygenVerifyKeyHex =
    'b4fe6eb7c9dee206a5b0a63ba8eff9a9ba3f5e5b348eb78fc10b6fa9c52490e2';

/// Entitlement code prefix that carries the tier.
const String _tierCodePrefix = 'TIER_';

/// The Keygen issuer: issuer one of the two `LicenseValidator` accepts.
///
/// Reads the three credential formats Keygen produces, and resolves them by
/// two different routes:
///
/// - A **licence key** carries a policy id and nothing else — no tier, no
///   product codes, no email, no seat count. It resolves through
///   [policies], the table compiled from the SKU catalog.
/// - A **licence file** embeds the whole licence object, entitlements
///   included. It resolves from those directly, and says so on the grant via
///   `resolvedFromEntitlements`.
/// - A **machine file** is a licence file checked out against one machine:
///   the machine is the document, the licence and its entitlements travel in
///   `included`, and the machine's fingerprint becomes the claim that binds
///   the credential to one install.
///
/// Embedded entitlements win when present, because they are as current as the
/// credential while the table is only as current as the build.
@immutable
class KeygenLicenseIssuer implements LicenseIssuer {
  /// Create an issuer against an explicit account, key and policy table.
  ///
  /// The parameters exist for tests, which sign fixtures with a throwaway
  /// keypair. Production code wants [KeygenLicenseIssuer.production].
  const KeygenLicenseIssuer({
    required this.accountId,
    required this.verifyKey,
    this.policies = kKeygenPolicies,
  });

  /// The live suite issuer: the real account, the real public key, and the
  /// generated policy table.
  KeygenLicenseIssuer.production()
    : accountId = kKeygenAccountId,
      verifyKey = decodeHexKey(kKeygenVerifyKeyHex),
      policies = kKeygenPolicies;

  @override
  String get id => 'keygen';

  @override
  final String? accountId;

  @override
  final List<int> verifyKey;

  /// Policy id to SKU, for resolving bare licence keys offline.
  final Map<String, KeygenPolicy> policies;

  @override
  LicenseClaims? claimsFrom(LicenseEnvelope envelope) =>
      switch (envelope.kind) {
        LicenseCredentialKind.licenseKey => _claimsFromKey(envelope.payload),
        LicenseCredentialKind.licenseFile => _claimsFromFile(envelope.payload),
        LicenseCredentialKind.machineFile => _claimsFromMachineFile(
          envelope.payload,
        ),
      };

  /// The licence key a file embeds, or `null` when [envelope] carries none.
  ///
  /// A bare key is not a file and answers `null` too — it *is* the key. A
  /// licence file carries the key on the licence it wraps; a machine file
  /// carries it on the licence included beside the machine. That key is what
  /// lets a file-activated machine register and release its seat, and ask
  /// the issuer whether the licence is still good: the file itself can be
  /// neither sent as an authorization header (it is multi-line) nor validated
  /// (it is not a key).
  static String? embeddedLicenseKey(LicenseEnvelope envelope) {
    final payload = envelope.payload;
    final license = switch (envelope.kind) {
      LicenseCredentialKind.licenseKey => null,
      LicenseCredentialKind.licenseFile => _object(payload['data']),
      LicenseCredentialKind.machineFile => _includedOfType(
        payload['included'],
        'licenses',
      ),
    };
    return _string(_object(license?['attributes'])?['key']);
  }

  @override
  LicenseGrant? grantFrom(LicenseClaims claims) {
    final tier = _tierFromEntitlements(claims.entitlementCodes);
    final products = _productsFromEntitlements(claims.entitlementCodes);
    if (tier != null && products.isNotEmpty) {
      return LicenseGrant(
        issuerId: id,
        tier: tier,
        products: products,
        licenseId: claims.licenseId,
        policyId: claims.policyId,
        skuLookupKey: policies[claims.policyId]?.stripeLookupKey,
        expiry: claims.expiry,
        maxMachines: claims.maxMachines,
        email: claims.email,
        resolvedFromEntitlements: true,
      );
    }

    final policy = policies[claims.policyId];
    if (policy == null) return null;
    return LicenseGrant(
      issuerId: id,
      tier: policy.tier,
      products: policy.products,
      licenseId: claims.licenseId,
      policyId: policy.id,
      skuLookupKey: policy.stripeLookupKey,
      expiry: claims.expiry,
      maxMachines: claims.maxMachines,
      email: claims.email,
    );
  }

  LicenseClaims _claimsFromKey(Map<String, Object?> payload) {
    final policy = _object(payload['policy']);
    final license = _object(payload['license']);
    final duration = _int(policy?['duration']);
    return LicenseClaims(
      issuerId: id,
      accountId: _string(_object(payload['account'])?['id']),
      productId: _string(_object(payload['product'])?['id']),
      policyId: _string(policy?['id']),
      policyDuration: duration == null ? null : Duration(seconds: duration),
      licenseId: _string(license?['id']),
      created: _time(license?['created']),
      expiry: _time(license?['expiry']),
      email: _string(_object(payload['user'])?['email']),
      raw: payload,
    );
  }

  /// Read a Keygen licence-file certificate.
  ///
  /// The payload is a JSON:API document: `data` is the licence, `included`
  /// carries the entitlements and the policy.
  LicenseClaims _claimsFromFile(Map<String, Object?> payload) =>
      _claimsFromLicence(
        _object(payload['data']),
        included: payload['included'],
        raw: payload,
      );

  /// Read a Keygen machine-file certificate.
  ///
  /// `data` is the machine; the licence it was checked out against travels in
  /// `included`, entitlements beside it, and the machine's fingerprint is the
  /// claim that binds the credential to one install. A machine file whose
  /// licence was not included resolves to nothing — there is no policy, no
  /// entitlement and no expiry to resolve — which is the right answer for a
  /// file issued without `include=license`.
  LicenseClaims _claimsFromMachineFile(Map<String, Object?> payload) {
    final machine = _object(payload['data']);
    final relationships = _object(machine?['relationships']);
    return _claimsFromLicence(
      _includedOfType(payload['included'], 'licenses'),
      included: payload['included'],
      raw: payload,
      fingerprint: _string(_object(machine?['attributes'])?['fingerprint']),
      accountId: _string(
        _object(_object(relationships?['account'])?['data'])?['id'],
      ),
    );
  }

  /// Claims from a licence resource plus the `included` list of the document
  /// it came in. Every lookup tolerates an absent or differently-typed field,
  /// because a validator that throws on a payload Keygen extended is a
  /// validator that locks out a paying customer.
  LicenseClaims _claimsFromLicence(
    Map<String, Object?>? data, {
    required Object? included,
    required Map<String, Object?> raw,
    String? fingerprint,
    String? accountId,
  }) {
    final attributes = _object(data?['attributes']);
    final relationships = _object(data?['relationships']);

    final codes = <String>{};
    String? policyId;
    if (included is List) {
      for (final entry in included) {
        final item = _object(entry);
        if (item == null) continue;
        switch (item['type']) {
          case 'entitlements':
            final code = _string(_object(item['attributes'])?['code']);
            if (code != null) codes.add(code.toUpperCase());
          case 'policies':
            policyId ??= _string(item['id']);
        }
      }
    }
    policyId ??= _string(
      _object(_object(relationships?['policy'])?['data'])?['id'],
    );
    return LicenseClaims(
      issuerId: id,
      accountId:
          _string(
            _object(_object(relationships?['account'])?['data'])?['id'],
          ) ??
          accountId,
      productId: _string(
        _object(_object(relationships?['product'])?['data'])?['id'],
      ),
      policyId: policyId,
      licenseId: _string(data?['id']),
      created: _time(attributes?['created']),
      expiry: _time(attributes?['expiry']),
      email: _string(_object(attributes?['metadata'])?['email']),
      maxMachines: _int(attributes?['maxMachines']),
      fingerprint: fingerprint,
      entitlementCodes: codes,
      raw: raw,
    );
  }

  LicenseTier? _tierFromEntitlements(Set<String> codes) {
    // Enterprise before Pro: a key carrying both is the higher of the two,
    // never the first one iterated.
    if (codes.contains('${_tierCodePrefix}ENTERPRISE')) {
      return LicenseTier.enterprise;
    }
    if (codes.contains('${_tierCodePrefix}PRO')) return LicenseTier.pro;
    if (codes.contains('${_tierCodePrefix}EDU')) return LicenseTier.edu;
    return null;
  }

  Set<CruxProduct> _productsFromEntitlements(Set<String> codes) {
    final products = <CruxProduct>{};
    for (final code in codes) {
      final product = CruxProduct.fromEntitlementCode(code);
      if (product != null) products.add(product);
    }
    return products;
  }
}

/// Decode a hex-encoded Ed25519 key into its 32 raw bytes.
///
/// Public because a second issuer, and every test fixture, needs the same
/// conversion. Throws [FormatException] on bad input — this is called with
/// compiled-in constants, never with user input, so a throw here is a build
/// bug and should be loud.
List<int> decodeHexKey(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('hex key has an odd length', hex);
  }
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (byte == null) throw FormatException('not hex', hex, i);
    bytes.add(byte);
  }
  return bytes;
}

Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// The first resource of [type] in a JSON:API `included` list, or `null`.
Map<String, Object?>? _includedOfType(Object? included, String type) {
  if (included is! List) return null;
  for (final entry in included) {
    final item = _object(entry);
    if (item != null && item['type'] == type) return item;
  }
  return null;
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// [value] as an int, or `null` when it is not a finite number.
///
/// JSON puts no bound on a number, and `1e400` decodes to `double.infinity`,
/// whose `toInt()` throws `UnsupportedError` — an Error, which walks through
/// every `on Exception` between here and the activation screen. A number
/// nothing can represent is unknown, the same as one of the wrong type.
int? _int(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
