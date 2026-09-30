// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/license_fixtures.dart';

/// The validator's refusals for a credential whose signature VERIFIES.
///
/// Forged, truncated and tampered credentials are covered where they belong:
/// the signature check refuses them, and `license_credential_fuzz_test.dart`
/// proves the parser in front of it is total. What neither reaches is the
/// other side of the signature — a payload a trusted key really did sign, in a
/// shape nothing here expected. A fuzzer cannot produce one, because it cannot
/// sign.
///
/// Two ways that happens, both tested here:
///
/// - **A second issuer.** The issuer set is plural so a self-issued EDU
///   licence can join Keygen as a configuration change. An issuer that
///   verifies a credential and then does not recognise its payload is its own
///   refusal, `undecodablePayload`, and nothing else in the suite reached it.
/// - **An issuer that extends its payload.** Keygen can add or retype fields.
///   Every lookup must then degrade to "unknown", because a validator that
///   throws on a payload its issuer extended locks out a paying customer — and
///   the validator promises, in its own class doc, never to throw.
void main() {
  late TestIssuerKeys keygenKeys;
  late TestIssuerKeys eduKeys;
  late CruxLicenseValidator validator;

  final duringTerm = DateTime.utc(2026, 9);

  setUpAll(() async {
    keygenKeys = await TestIssuerKeys.fromSeed(7);
    eduKeys = await TestIssuerKeys.fromSeed(23);
    validator = CruxLicenseValidator(
      product: CruxProduct.waveCrux,
      issuers: <LicenseIssuer>[
        KeygenLicenseIssuer(
          accountId: testAccountId,
          verifyKey: keygenKeys.verifyKey,
          policies: testPolicies,
        ),
        _SelfIssuedEduIssuer(eduKeys.verifyKey),
      ],
    );
  });

  /// Validate, and fail the test — rather than let it error — if anything is
  /// thrown, so the failure says the promise broke rather than where.
  Future<LicenseValidation> validate(String credential) async {
    try {
      return await validator.validate(credential, now: duringTerm);
    } on Object catch (error) {
      fail(
        'validate threw ${error.runtimeType} ($error) — it promises to '
        'return a LicenseValidation for every input',
      );
    }
  }

  test('the About box can tell the real validator from the no-op', () {
    // A build that shipped the no-op validator would grant nothing to anyone
    // and look, from the outside, like every customer's key had stopped
    // working. The name is how a support bundle tells the two apart.
    expect(validator.name, 'ed25519');
    expect(const NoopLicenseValidator().name, 'noop');
  });

  group('a second issuer that does not recognise the payload', () {
    test('its own shape resolves — the slot is real', () async {
      final credential = await eduKeys.mintKey(<String, Object?>{
        'edu': <String, Object?>{
          'email': 'student@uni.example',
          'expires': '2027-06-30T00:00:00Z',
        },
      });

      final result = await validate(credential);

      expect(result, isA<LicenseAccepted>());
      expect(result.grant!.issuerId, 'edu-self');
      expect(result.grant!.tier, LicenseTier.edu);
    });

    test('a shape it does not know is refused by name', () async {
      // Signed by the EDU key, so the signature verifies — but in Keygen's
      // payload shape, which the EDU issuer has never heard of.
      final credential = await eduKeys.mintKey(keyPayload());

      final result = await validate(credential);

      expect(result, isA<LicenseRejected>());
      final rejected = result as LicenseRejected;
      expect(rejected.reason, LicenseRejection.undecodablePayload);
      expect(
        rejected.detail,
        contains('edu-self'),
        reason: 'support needs to know which issuer could not read it',
      );
      expect(result.grant, isNull);
    });

    test('and is not handed to another issuer to try', () async {
      // The issuer that verified the signature owns the credential. Offering
      // it to the next issuer in the list would let a payload one issuer
      // signed be read under another issuer's rules.
      final credential = await eduKeys.mintKey(keyPayload());
      final keygenFirst = CruxLicenseValidator(
        product: CruxProduct.waveCrux,
        issuers: <LicenseIssuer>[
          _SelfIssuedEduIssuer(eduKeys.verifyKey),
          KeygenLicenseIssuer(
            accountId: testAccountId,
            verifyKey: eduKeys.verifyKey,
            policies: testPolicies,
          ),
        ],
      );

      final result = await keygenFirst.validate(credential, now: duringTerm);

      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.undecodablePayload,
      );
    });
  });

  group('a Keygen payload whose fields are the wrong type', () {
    // Each of these is signed by the trusted key. Each must come back as a
    // refusal — never a grant, and never a throw.
    final hostile = <String, Map<String, Object?> Function()>{
      'account is a string': () => keyPayload()..['account'] = 'acc0',
      'account is a list': () => keyPayload()..['account'] = <Object?>[1],
      'account is missing': () => keyPayload()..remove('account'),
      'account id is a number': () =>
          keyPayload()..['account'] = <String, Object?>{'id': 7},
      'policy is a string': () => keyPayload()..['policy'] = 'p',
      'policy id is a number': () =>
          keyPayload()..['policy'] = <String, Object?>{'id': 12},
      'everything is null': () => <String, Object?>{
        'account': null,
        'product': null,
        'policy': null,
        'user': null,
        'license': null,
      },
      'the payload is empty': () => <String, Object?>{},
    };

    for (final entry in hostile.entries) {
      test(entry.key, () async {
        final result = await validate(
          await keygenKeys.mintKey(entry.value()),
        );
        expect(result, isA<LicenseRejected>(), reason: entry.key);
        expect(result.grant, isNull);
      });
    }

    test('a garbage expiry reads as none, not as a crash', () async {
      // Keygen writes `expiry: null` for a perpetual licence, so an absent
      // or unreadable one resolving the same way is consistent, not a hole:
      // only the issuer's key can produce the payload.
      final payload = keyPayload();
      (payload['license']! as Map<String, Object?>)['expiry'] = 'next spring';

      final result = await validate(await keygenKeys.mintKey(payload));

      expect(result, isA<LicenseAccepted>());
      expect(result.grant!.expiry, isNull);
    });

    test('an unreadable licence section reads as unknown, too', () async {
      // Account and policy still say who issued it and what it grants; the
      // licence section only adds an id and dates, and without it both are
      // unknown rather than invented.
      final result = await validate(
        await keygenKeys.mintKey(keyPayload()..['license'] = <Object?>['x']),
      );

      expect(result, isA<LicenseAccepted>());
      expect(result.grant!.licenseId, isNull);
      expect(result.grant!.expiry, isNull);
    });

    test('a licence file whose sections are the wrong type', () async {
      for (final (label, mutate)
          in <(String, void Function(Map<String, Object?>))>[
            ('data is a list', (f) => f['data'] = <Object?>[]),
            (
              'attributes is a string',
              (f) {
                (f['data']! as Map<String, Object?>)['attributes'] = 'x';
              },
            ),
            (
              'relationships is a number',
              (f) {
                (f['data']! as Map<String, Object?>)['relationships'] = 3;
              },
            ),
            ('included is a map', (f) => f['included'] = <String, Object?>{}),
            (
              'an entitlement code is a number',
              (f) {
                f['included'] = <Object?>[
                  <String, Object?>{
                    'type': 'entitlements',
                    'attributes': <String, Object?>{'code': 7},
                  },
                ];
              },
            ),
          ]) {
        // No embedded entitlements and a policy this build does not know, so
        // the only way to a grant is reading the sections being broken.
        final payload = filePayload(
          policy: 'p-not-in-this-build',
          entitlements: const <String>[],
        );
        mutate(payload);
        final result = await validate(await keygenKeys.mintFile(payload));
        expect(result, isA<LicenseRejected>(), reason: label);
      }
    });
  });

  group('a number too large for an int', () {
    // JSON has no size limit on a number, and `1e400` decodes to
    // double.infinity. `Infinity.toInt()` throws UnsupportedError — an Error,
    // which walks straight through every `on Exception` between the validator
    // and the activation screen. Two claims read a number: a key's policy
    // duration and a file's seat count.
    test('in a licence key policy duration', () async {
      final credential = _mintRawKey(
        keygenKeys,
        '{"account":{"id":"$testAccountId"},'
        '"policy":{"id":"$testWaveCruxProPolicyId","duration":1e400},'
        '"license":{"id":"lic-1","expiry":"2027-01-01T00:00:00Z"}}',
      );

      final result = await validate(credential);

      expect(result, isA<LicenseAccepted>());
      expect(result.grant!.tier, LicenseTier.pro);
    });

    test('in a licence file seat count', () async {
      final payload = jsonEncode(filePayload()).replaceFirst(
        '"maxMachines":5',
        '"maxMachines":-1e400',
      );
      expect(payload, contains('-1e400'), reason: 'the fixture was edited');

      final result = await validate(_mintRawFile(keygenKeys, payload));

      expect(result, isA<LicenseAccepted>());
      expect(
        result.grant!.maxMachines,
        isNull,
        reason: 'a seat count nobody can represent is unknown, not a number',
      );
    });

    test('a large but finite seat count is still read', () async {
      final payload = jsonEncode(
        filePayload(),
      ).replaceFirst('"maxMachines":5', '"maxMachines":2.5e3');

      final result = await validate(_mintRawFile(keygenKeys, payload));

      expect(result.grant!.maxMachines, 2500);
    });

    test('in an issuer answer the client reads', () {
      // The same field shape arrives signed from the issuer's API, and is
      // read by the same kind of helper.
      final answer = KeygenValidation.fromBody(const <String, Object?>{
        'meta': {'valid': true, 'code': 'VALID'},
        'data': {
          'id': 'lic-1',
          'attributes': {
            'maxMachines': double.infinity,
            'machinesCount': double.negativeInfinity,
          },
        },
      });

      expect(answer.valid, isTrue);
      expect(answer.maxMachines, isNull);
      expect(answer.machineCount, isNull);
    });
  });
}

/// A self-issued EDU issuer: the reserved second slot, in a claim shape of
/// its own. Recognises `{"edu": {"email", "expires"}}` and nothing else.
class _SelfIssuedEduIssuer implements LicenseIssuer {
  _SelfIssuedEduIssuer(this.verifyKey);

  @override
  final List<int> verifyKey;

  @override
  String get id => 'edu-self';

  @override
  String? get accountId => null;

  @override
  LicenseClaims? claimsFrom(LicenseEnvelope envelope) {
    final edu = envelope.payload['edu'];
    if (edu is! Map<String, Object?>) return null;
    final expires = edu['expires'];
    return LicenseClaims(
      issuerId: id,
      email: edu['email'] is String ? edu['email']! as String : null,
      expiry: expires is String ? DateTime.tryParse(expires) : null,
      entitlementCodes: const <String>{'TIER_EDU', 'WAVECRUX'},
      raw: envelope.payload,
    );
  }

  @override
  LicenseGrant? grantFrom(LicenseClaims claims) => LicenseGrant(
    issuerId: id,
    tier: LicenseTier.edu,
    products: const <CruxProduct>{CruxProduct.waveCrux},
    expiry: claims.expiry,
    email: claims.email,
  );
}

/// base64url, padding stripped — the alphabet Keygen emits.
String _b64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll(RegExp(r'=+$'), '');

/// A licence key over the exact JSON text [payload], which `jsonEncode`
/// cannot produce when the point of the test is a number it refuses to write.
String _mintRawKey(TestIssuerKeys keys, String payload) {
  final encoded = _b64(utf8.encode(payload));
  final signature = keys.signBytes(utf8.encode('key/$encoded'));
  return 'key/$encoded.${_b64(signature)}';
}

/// A licence file over the exact JSON text [payload].
String _mintRawFile(TestIssuerKeys keys, String payload) {
  final enc = _b64(utf8.encode(payload));
  final certificate = jsonEncode(<String, Object?>{
    'enc': enc,
    'sig': _b64(keys.signBytes(utf8.encode('license/$enc'))),
    'alg': 'base64+ed25519',
  });
  return '-----BEGIN LICENSE FILE-----\n'
      '${base64.encode(utf8.encode(certificate))}\n'
      '-----END LICENSE FILE-----\n';
}
