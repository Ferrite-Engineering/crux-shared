// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:crux_license/src/keygen_policy_table.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/edu_fixtures.dart';
import 'support/license_fixtures.dart';

/// The self-issued educational licence (`edu-v1`) and the issuer that reads
/// it.
///
/// What is guarded: the shared vector verifies, so this side and the signing
/// side agree on the format; every way a credential can be wrong is refused
/// the way a Keygen credential would be; the grant is exactly the
/// `edu-annual` grant; and a production build trusts no test key.
void main() {
  final vector = EduVector.load();
  final insideTerm = DateTime.utc(2027, 3);

  late TestIssuerKeys keys;
  late TestIssuerKeys otherKeys;

  setUpAll(() async {
    keys = await TestIssuerKeys.fromSeed(41);
    otherKeys = await TestIssuerKeys.fromSeed(42);
  });

  CruxLicenseValidator validatorOn(
    List<int> verifyKey, {
    CruxProduct product = CruxProduct.waveCrux,
  }) => CruxLicenseValidator(
    product: product,
    issuers: <LicenseIssuer>[
      EduLicenseIssuer(keyId: 'edu-test', verifyKey: verifyKey),
    ],
  );

  KeygenPolicy eduAnnual() =>
      kKeygenPolicies.values.singleWhere((p) => p.name == 'edu-annual');

  group('the shared vector', () {
    test('parses as an educational licence', () {
      final envelope = parseLicenseCredential(vector.credential).envelope!;
      expect(envelope.kind, LicenseCredentialKind.eduKey);
      expect(envelope.payload, vector.payload);
    });

    for (final product in CruxProduct.values) {
      test('verifies with the test key, for ${product.displayName}', () async {
        final result = await validatorOn(
          vector.publicKey,
          product: product,
        ).validate(vector.credential, now: insideTerm);

        expect(result, isA<LicenseAccepted>());
        final grant = result.grant!;
        expect(grant.issuerId, kEduLicenseIssuerId);
        expect(grant.tier, LicenseTier.edu);
        expect(grant.products, CruxProduct.values.toSet());
        expect(grant.licenseId, vector.payload['id']);
        expect(grant.email, vector.payload['email']);
        expect(grant.expiry, DateTime.parse(vector.payload['exp']! as String));
        expect(grant.issued, DateTime.parse(vector.payload['iat']! as String));
        expect(grant.isEvaluation, isFalse);
        expect(grant.maxMachines, isNull);
      });
    }

    test('grants exactly what an edu-annual Keygen licence grants', () async {
      final grant = (await validatorOn(
        vector.publicKey,
      ).validate(vector.credential, now: insideTerm)).grant!;
      final policy = eduAnnual();
      expect(grant.tier, policy.tier);
      expect(grant.products, policy.products);
      expect(grant.skuLookupKey, policy.stripeLookupKey);
    });

    test('is refused under a key that did not sign it', () async {
      final result = await validatorOn(
        otherKeys.verifyKey,
      ).validate(vector.credential, now: insideTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('a tampered payload is refused', () async {
      final dot = vector.credential.lastIndexOf('.');
      final payload = Map<String, Object?>.of(vector.payload)
        ..['email'] = 'someone-else@example.edu';
      final forged =
          'edu/${b64Url(utf8.encode(json.encode(payload)))}'
          '${vector.credential.substring(dot)}';

      final result = await validatorOn(
        vector.publicKey,
      ).validate(forged, now: insideTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('a tampered signature is refused', () async {
      final dot = vector.credential.lastIndexOf('.');
      final signature = vector.credential.substring(dot + 1);
      // Change one character in the middle, keeping the length and alphabet.
      final at = signature.length ~/ 2;
      final flipped = signature[at] == 'A' ? 'B' : 'A';
      final forged =
          '${vector.credential.substring(0, dot + 1)}'
          '${signature.substring(0, at)}$flipped${signature.substring(at + 1)}';

      final result = await validatorOn(
        vector.publicKey,
      ).validate(forged, now: insideTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('past its expiry it is expired, grant in hand for grace', () async {
      final result = await validatorOn(
        vector.publicKey,
      ).validate(vector.credential, now: DateTime.utc(2027, 11, 17));
      expect(result, isA<LicenseExpired>());
      expect(result.grant!.tier, LicenseTier.edu);
    });

    test('before it was issued it is refused', () async {
      final result = await validatorOn(
        vector.publicKey,
      ).validate(vector.credential, now: DateTime.utc(2026, 11, 12));
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.undecodablePayload,
      );
      expect(result.detail, contains('not valid until'));
    });

    test('a clock a few hours behind the issuer still accepts it', () async {
      // The commerce backend signs with its own clock, and an exchanged
      // licence is validated the moment it arrives.
      final result = await validatorOn(
        vector.publicKey,
      ).validate(vector.credential, now: DateTime.utc(2026, 11, 14, 20));
      expect(result, isA<LicenseAccepted>());
    });

    test(
      'pasted in standard base64, padded and wrapped, it verifies',
      () async {
        final dot = vector.credential.lastIndexOf('.');
        String standard(String text) {
          final out = text.replaceAll('-', '+').replaceAll('_', '/');
          return out.padRight(out.length + (4 - out.length % 4) % 4, '=');
        }

        final payload = standard(vector.credential.substring(4, dot));
        final signature = standard(vector.credential.substring(dot + 1));
        expect(
          '$payload$signature',
          anyOf(contains('+'), contains('/'), contains('=')),
          reason: 'the paste must actually differ from the issued form',
        );
        final wrapped = <String>[
          for (var i = 0; i < payload.length; i += 60)
            payload.substring(
              i,
              i + 60 > payload.length ? payload.length : i + 60,
            ),
        ].join('\n');
        final pasted = '  edu/$wrapped.$signature\n';

        final result = await validatorOn(
          vector.publicKey,
        ).validate(pasted, now: insideTerm);
        expect(result, isA<LicenseAccepted>());
        expect(result.grant!.licenseId, vector.payload['id']);
      },
    );

    test('every prefix of it parses without throwing', () {
      for (var i = 0; i <= vector.credential.length; i++) {
        expect(
          () => parseLicenseCredential(vector.credential.substring(0, i)),
          returnsNormally,
        );
      }
    });
  });

  group('the payload', () {
    Future<LicenseValidation> validate(
      Map<String, Object?> payload, {
      CruxProduct product = CruxProduct.waveCrux,
    }) => validatorOn(
      keys.verifyKey,
      product: product,
    ).validate(mintEdu(keys, payload), now: DateTime.utc(2026, 9));

    test('a well-formed one is accepted', () async {
      expect(await validate(eduPayload()), isA<LicenseAccepted>());
    });

    test('a typ other than edu is refused', () async {
      final result = await validate(eduPayload(typ: 'pro'));
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.undecodablePayload,
      );
    });

    test('a version other than 1 is refused', () async {
      for (final v in <Object?>[2, 0, '1', null]) {
        final result = await validate(eduPayload(v: v));
        expect(
          (result as LicenseRejected).reason,
          LicenseRejection.undecodablePayload,
          reason: 'v: $v',
        );
      }
    });

    test('unknown extra fields are ignored', () async {
      final payload = eduPayload()..['school'] = 'anything';
      expect(await validate(payload), isA<LicenseAccepted>());
    });

    test('no readable expiry is refused, never read as perpetual', () async {
      for (final exp in <Object?>[null, 'soon', 20270101]) {
        final result = await validate(eduPayload(exp: exp));
        expect(
          (result as LicenseRejected).reason,
          LicenseRejection.undecodablePayload,
          reason: 'exp: $exp',
        );
      }
    });

    test('no readable issue time is refused', () async {
      final result = await validate(eduPayload(iat: null));
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.undecodablePayload,
      );
    });

    test('products are the listed ones this build knows', () async {
      final payload = eduPayload(
        products: const <String>['wavecrux', 'futurecrux'],
      );
      final accepted = await validate(payload);
      expect(accepted.grant!.products, <CruxProduct>{CruxProduct.waveCrux});

      final other = await validate(payload, product: CruxProduct.netCrux);
      expect(
        (other as LicenseRejected).reason,
        LicenseRejection.productNotEntitled,
      );
    });

    test('a licence for no known product grants nothing', () async {
      for (final products in <Object?>[
        const <String>[],
        const <String>['futurecrux'],
        'wavecrux',
      ]) {
        final result = await validate(eduPayload(products: products));
        expect(
          (result as LicenseRejected).reason,
          LicenseRejection.unknownPolicy,
          reason: 'products: $products',
        );
      }
    });
  });

  group('the two issuers stay apart', () {
    test(
      "an edu credential signed by the Keygen key is not Keygen's",
      () async {
        final validator = CruxLicenseValidator(
          product: CruxProduct.waveCrux,
          issuers: <LicenseIssuer>[
            KeygenLicenseIssuer(
              accountId: testAccountId,
              verifyKey: keys.verifyKey,
              policies: testPolicies,
            ),
          ],
        );
        final result = await validator.validate(
          mintEdu(keys, eduPayload()),
          now: DateTime.utc(2026, 9),
        );
        expect(
          (result as LicenseRejected).reason,
          LicenseRejection.undecodablePayload,
        );
      },
    );

    test(
      "a Keygen key signed by the edu key is not the edu issuer's",
      () async {
        final result = await validatorOn(keys.verifyKey).validate(
          await keys.mintKey(keyPayload()),
          now: DateTime.utc(2026, 9),
        );
        expect(
          (result as LicenseRejected).reason,
          LicenseRejection.undecodablePayload,
        );
      },
    );

    test('an edu credential has no key to present to Keygen', () {
      final envelope = parseLicenseCredential(vector.credential).envelope!;
      expect(KeygenLicenseIssuer.embeddedLicenseKey(envelope), isNull);
    });
  });

  group('production', () {
    test('trusts Keygen and both educational keys, in that order', () {
      final issuers = CruxLicenseValidator.production(
        product: CruxProduct.waveCrux,
      ).issuers;
      expect(issuers, hasLength(3));
      expect(issuers.first, isA<KeygenLicenseIssuer>());
      final edu = issuers.skip(1).cast<EduLicenseIssuer>().toList();
      expect(edu.map((i) => i.keyId), <String>['edu-2026-a', 'edu-2026-b']);
      for (final issuer in edu) {
        expect(issuer.verifyKey, hasLength(32));
        expect(issuer.accountId, isNull);
        expect(issuer.id, kEduLicenseIssuerId);
      }
      expect(edu[0].verifyKey, isNot(edu[1].verifyKey));
    });

    test("does not trust the test vector's key", () async {
      final result = await CruxLicenseValidator.production(
        product: CruxProduct.waveCrux,
      ).validate(vector.credential, now: insideTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
      for (final issuer in EduLicenseIssuer.production()) {
        expect(issuer.verifyKey, isNot(vector.publicKey));
      }
    });
  });

  test('an educational licence may be kept in the fallback file', () {
    expect(licenseCredentialMayUseFallbackFile(vector.credential), isTrue);
  });
}
