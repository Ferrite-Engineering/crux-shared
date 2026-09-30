// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';

import 'ed25519_sign.dart';

/// A throwaway Ed25519 keypair and the credential minting that goes with it.
///
/// **Nothing here is ever signed by the production key.** Keygen holds that
/// private key and we could not sign with it if we wanted to; these fixtures
/// are minted from a fixed 32-byte seed so the suite is deterministic without
/// committing a single byte of real key material.
class TestIssuerKeys {
  TestIssuerKeys._(this._pair);

  /// Derive a keypair from [seed] — any byte, expanded to the 32 the
  /// algorithm wants.
  static Future<TestIssuerKeys> fromSeed(int seed) async => TestIssuerKeys._(
    TestEd25519KeyPair.fromSeed(List<int>.filled(32, seed & 0xff)),
  );

  final TestEd25519KeyPair _pair;

  /// The public key as the raw bytes an issuer is configured with.
  List<int> get verifyKey => _pair.publicKey;

  Future<String> _sign(String message) async =>
      _b64(_pair.sign(utf8.encode(message)));

  /// Sign arbitrary bytes, returning the raw 64-byte signature.
  ///
  /// For fixtures that are not credentials: the issuer signs every API
  /// response it sends, and a fake issuer has to sign its answers with the
  /// same throwaway key the validator is configured with or the client
  /// refuses them as unverified.
  List<int> signBytes(List<int> message) => _pair.sign(message);

  /// Mint a Keygen-shaped licence key over [payload].
  ///
  /// Reproduces the real format exactly — base64url payload, a dot, base64url
  /// signature — with the signature taken over the `key/` prefix plus the
  /// *encoded* payload rather than the JSON, which is what makes verification
  /// independent of JSON canonicalisation.
  Future<String> mintKey(Map<String, Object?> payload) async {
    final encoded = _b64(utf8.encode(json.encode(payload)));
    return 'key/$encoded.${await _sign('key/$encoded')}';
  }

  /// Mint the licence file this build deliberately CANNOT open: the same
  /// signed envelope, but `alg: aes-256-gcm+ed25519`.
  ///
  /// A legitimate Keygen format, and one the portal will happily issue by
  /// mistake — it encrypts the payload with the licence key as the secret, so
  /// a pasted file alone can never be opened. The body here is not really
  /// encrypted; nothing in this package would decrypt it if it were, and the
  /// `alg` check refuses the file before the payload is ever looked at. What
  /// the fixture reproduces is exactly what the parser sees.
  Future<String> mintEncryptedFile(Map<String, Object?> payload) async {
    final enc = _b64(utf8.encode(json.encode(payload)));
    final certificate = json.encode(<String, Object?>{
      'enc': enc,
      'sig': await _sign('license/$enc'),
      'alg': 'aes-256-gcm+ed25519',
    });
    final body = base64.encode(utf8.encode(certificate));
    return '-----BEGIN LICENSE FILE-----\n'
        '${_wrap(body)}\n'
        '-----END LICENSE FILE-----\n';
  }

  /// Mint a Keygen-shaped, signed-but-unencrypted licence file over
  /// [payload].
  Future<String> mintFile(Map<String, Object?> payload) async {
    final enc = _b64(utf8.encode(json.encode(payload)));
    final certificate = json.encode(<String, Object?>{
      'enc': enc,
      'sig': await _sign('license/$enc'),
      'alg': 'base64+ed25519',
    });
    final body = base64.encode(utf8.encode(certificate));
    return '-----BEGIN LICENSE FILE-----\n'
        '${_wrap(body)}\n'
        '-----END LICENSE FILE-----\n';
  }

  /// Mint a Keygen-shaped machine file over [payload]: the same certificate
  /// as a licence file, under `MACHINE FILE` markers and signed over the
  /// `machine/` prefix.
  Future<String> mintMachineFile(Map<String, Object?> payload) async {
    final enc = _b64(utf8.encode(json.encode(payload)));
    final certificate = json.encode(<String, Object?>{
      'enc': enc,
      'sig': await _sign('machine/$enc'),
      'alg': 'base64+ed25519',
    });
    final body = base64.encode(utf8.encode(certificate));
    return '-----BEGIN MACHINE FILE-----\n'
        '${_wrap(body)}\n'
        '-----END MACHINE FILE-----\n';
  }
}

/// base64url, padding stripped — the alphabet Keygen emits.
String _b64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll(RegExp(r'=+$'), '');

String _wrap(String text) {
  final lines = <String>[];
  for (var i = 0; i < text.length; i += 64) {
    lines.add(text.substring(i, i + 64 > text.length ? text.length : i + 64));
  }
  return lines.join('\n');
}

/// The account id fixture credentials claim.
const String testAccountId = 'acc0acc0-0000-4000-8000-000000000001';

/// A policy id the test table knows about: WaveCrux Pro, monthly.
const String testWaveCruxProPolicyId = 'p0000000-0000-4000-8000-00000000000a';

/// A policy id the test table knows about: the whole suite at Enterprise.
const String testSuiteEnterprisePolicyId =
    'p0000000-0000-4000-8000-00000000000b';

/// A stand-in for the compiled production table, small enough to reason about.
const Map<String, KeygenPolicy> testPolicies = <String, KeygenPolicy>{
  testWaveCruxProPolicyId: KeygenPolicy(
    id: testWaveCruxProPolicyId,
    name: 'wavecrux-pro-monthly',
    tier: LicenseTier.pro,
    products: <CruxProduct>{CruxProduct.waveCrux},
    duration: Duration(seconds: 2678400),
    stripeLookupKey: 'wavecrux-pro-monthly',
  ),
  testSuiteEnterprisePolicyId: KeygenPolicy(
    id: testSuiteEnterprisePolicyId,
    name: 'suite-ent-annual',
    tier: LicenseTier.enterprise,
    products: <CruxProduct>{
      CruxProduct.waveCrux,
      CruxProduct.netCrux,
      CruxProduct.lintCrux,
      CruxProduct.simCrux,
    },
    duration: Duration(seconds: 31622400),
    stripeLookupKey: 'suite-ent-annual',
  ),
};

/// The licence-key payload Keygen actually issues: an account, a product, a
/// policy, a null user, and the licence itself. No entitlements, no tier, no
/// email, no seat count — which is the whole reason the policy table exists.
Map<String, Object?> keyPayload({
  String account = testAccountId,
  String policy = testWaveCruxProPolicyId,
  String? expiry = '2027-01-01T00:00:00.000Z',
  int duration = 2678400,
}) => <String, Object?>{
  'account': <String, Object?>{'id': account},
  'product': <String, Object?>{'id': 'prod0000-0000-4000-8000-000000000001'},
  'policy': <String, Object?>{'id': policy, 'duration': duration},
  'user': null,
  'license': <String, Object?>{
    'id': 'lic00000-0000-4000-8000-000000000001',
    'created': '2026-08-01T00:00:00.000Z',
    'expiry': expiry,
  },
};

/// A licence-file payload: the JSON:API document Keygen wraps in a
/// `-----BEGIN LICENSE FILE-----` envelope, entitlements included.
Map<String, Object?> filePayload({
  String account = testAccountId,
  String policy = testWaveCruxProPolicyId,
  String? expiry = '2027-01-01T00:00:00.000Z',
  int maxMachines = 5,
  List<String> entitlements = const <String>['WAVECRUX', 'TIER_PRO'],
  String email = 'buyer@example.com',
  String? key,
}) => <String, Object?>{
  'meta': <String, Object?>{
    'issued': '2026-08-01T00:00:00.000Z',
    'ttl': 2678400,
  },
  'data': <String, Object?>{
    'type': 'licenses',
    'id': 'lic00000-0000-4000-8000-000000000001',
    'attributes': <String, Object?>{
      'key': ?key,
      'created': '2026-08-01T00:00:00.000Z',
      'expiry': expiry,
      'maxMachines': maxMachines,
      'metadata': <String, Object?>{'email': email},
    },
    'relationships': <String, Object?>{
      'account': <String, Object?>{
        'data': <String, Object?>{'type': 'accounts', 'id': account},
      },
      'policy': <String, Object?>{
        'data': <String, Object?>{'type': 'policies', 'id': policy},
      },
    },
  },
  'included': <Object?>[
    for (final code in entitlements)
      <String, Object?>{
        'type': 'entitlements',
        'id': 'ent-$code',
        'attributes': <String, Object?>{'code': code},
      },
  ],
};

/// A machine-file payload: the JSON:API document Keygen wraps in a
/// `-----BEGIN MACHINE FILE-----` envelope. `data` is the machine — carrying
/// the [fingerprint] it was checked out for — and the licence it belongs to
/// travels in `included`, entitlements beside it.
Map<String, Object?> machineFilePayload({
  String fingerprint = 'fingerprint-1',
  String account = testAccountId,
  String policy = testWaveCruxProPolicyId,
  String? expiry = '2027-01-01T00:00:00.000Z',
  int maxMachines = 5,
  List<String> entitlements = const <String>['WAVECRUX', 'TIER_PRO'],
  String email = 'buyer@example.com',
  String? key,
}) {
  final license = filePayload(
    account: account,
    policy: policy,
    expiry: expiry,
    maxMachines: maxMachines,
    entitlements: entitlements,
    email: email,
    key: key,
  );
  return <String, Object?>{
    'meta': <String, Object?>{
      'issued': '2026-08-01T00:00:00.000Z',
      'ttl': 31622400,
    },
    'data': <String, Object?>{
      'type': 'machines',
      'id': 'mach0000-0000-4000-8000-000000000001',
      'attributes': <String, Object?>{
        'fingerprint': fingerprint,
        'name': 'lab-01',
        'platform': 'macos',
      },
      'relationships': <String, Object?>{
        'account': <String, Object?>{
          'data': <String, Object?>{'type': 'accounts', 'id': account},
        },
        'license': <String, Object?>{
          'data': <String, Object?>{
            'type': 'licenses',
            'id': (license['data']! as Map<String, Object?>)['id'],
          },
        },
      },
    },
    'included': <Object?>[
      license['data'],
      ...license['included']! as List<Object?>,
    ],
  };
}
