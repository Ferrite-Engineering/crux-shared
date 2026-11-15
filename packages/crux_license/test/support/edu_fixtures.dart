// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'license_fixtures.dart';

/// The shared `edu-v1` test vector: a test-only public key, a payload, and
/// the credential its private half signed. The commerce backend's tests
/// verify the same credential, which is what keeps the two sides of the
/// format in step.
class EduVector {
  EduVector._(this.publicKey, this.payload, this.credential);

  /// Read `test/fixtures/edu-v1-vector.json`.
  factory EduVector.load() {
    final json =
        jsonDecode(File('test/fixtures/edu-v1-vector.json').readAsStringSync())
            as Map<String, Object?>;
    return EduVector._(
      base64.decode(json['publicKeyBase64']! as String),
      json['payload']! as Map<String, Object?>,
      json['credential']! as String,
    );
  }

  /// The raw 32-byte public key.
  final List<int> publicKey;

  /// The payload, decoded.
  final Map<String, Object?> payload;

  /// `edu/<payload>.<signature>`.
  final String credential;
}

/// An `edu-v1` payload, with any field overridable.
Map<String, Object?> eduPayload({
  Object? v = 1,
  Object? typ = 'edu',
  String id = 'edu00000-0000-4000-8000-000000000001',
  String email = 'student@example.edu',
  Object? products = const <String>[
    'wavecrux',
    'netcrux',
    'lintcrux',
    'simcrux',
  ],
  Object? iat = '2026-08-01T00:00:00Z',
  Object? exp = '2027-08-02T00:00:00Z',
  String src = 'request',
}) => <String, Object?>{
  'v': v,
  'typ': typ,
  'kid': 'edu-test',
  'id': id,
  'email': email,
  'products': products,
  'iat': ?iat,
  'exp': ?exp,
  'src': src,
};

/// Sign [payload] as the educational issuer does: base64url without padding,
/// and an Ed25519 signature over `edu/` plus the encoded payload.
String mintEdu(TestIssuerKeys keys, Map<String, Object?> payload) {
  final encoded = b64Url(utf8.encode(json.encode(payload)));
  return 'edu/$encoded.${b64Url(keys.signBytes(utf8.encode('edu/$encoded')))}';
}

/// base64url, padding stripped.
String b64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll(RegExp(r'=+$'), '');
