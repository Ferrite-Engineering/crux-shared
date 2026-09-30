// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/license_fixtures.dart';

/// The cryptographic validator, end to end.
///
/// Fixtures are minted here from a throwaway keypair (see
/// `support/license_fixtures.dart`): the production private key is Keygen's
/// and never leaves them, so nothing in this repo can — or should — carry
/// something it signed.
void main() {
  late TestIssuerKeys keys;
  late KeygenLicenseIssuer issuer;
  late CruxLicenseValidator validator;

  /// A moment comfortably inside every fixture's validity window.
  final duringTerm = DateTime.utc(2026, 9);

  setUpAll(() async {
    keys = await TestIssuerKeys.fromSeed(7);
    issuer = KeygenLicenseIssuer(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      policies: testPolicies,
    );
    validator = CruxLicenseValidator(
      product: CruxProduct.waveCrux,
      issuers: <LicenseIssuer>[issuer],
    );
  });

  group('no credential', () {
    test('null, empty and whitespace are Open Core, not errors', () async {
      expect(await validator.validate(null), isA<LicenseAbsent>());
      expect(await validator.validate(''), isA<LicenseAbsent>());
      expect(await validator.validate('   \n '), isA<LicenseAbsent>());
      expect(
        (await validator.validate(null)).tier,
        LicenseTier.openCore,
        reason: 'Open Core is the absence of a licence',
      );
    });
  });

  group('a valid licence key', () {
    test('resolves tier and product through the policy table', () async {
      final key = await keys.mintKey(keyPayload());
      final result = await validator.validate(key, now: duringTerm);

      expect(result, isA<LicenseAccepted>());
      final grant = result.grant!;
      expect(grant.tier, LicenseTier.pro);
      expect(grant.products, <CruxProduct>{CruxProduct.waveCrux});
      expect(grant.skuLookupKey, 'wavecrux-pro-monthly');
      expect(grant.issuerId, 'keygen');
      expect(grant.expiry, DateTime.utc(2027));
      expect(
        grant.resolvedFromEntitlements,
        isFalse,
        reason: 'a bare key carries no entitlements at all',
      );
      expect(result.tier, LicenseTier.pro);
    });

    test('survives the whitespace a mail client adds', () async {
      final key = await keys.mintKey(keyPayload());
      final dot = key.lastIndexOf('.');
      final signature = key.substring(dot + 1);
      final rewrapped = <String>[
        for (var i = 0; i < signature.length; i += 20)
          signature.substring(
            i,
            i + 20 > signature.length ? signature.length : i + 20,
          ),
      ].join('\n');
      // Only the signature half is re-wrapped; the payload half stays
      // byte-identical, because it is what was signed.
      final tolerated = '  ${key.substring(0, dot)}.$rewrapped  ';
      expect(
        await validator.validate(tolerated, now: duringTerm),
        isA<LicenseAccepted>(),
      );
    });

    test('a Suite key unlocks every product at the same tier', () async {
      final key = await keys.mintKey(
        keyPayload(policy: testSuiteEnterprisePolicyId),
      );
      for (final product in CruxProduct.values) {
        final each = CruxLicenseValidator(
          product: product,
          issuers: <LicenseIssuer>[issuer],
        );
        final result = await each.validate(key, now: duringTerm);
        expect(result, isA<LicenseAccepted>(), reason: product.name);
        expect(result.grant!.tier, LicenseTier.enterprise);
      }
    });
  });

  group('rejections', () {
    test('garbage input is rejected, and nothing throws', () async {
      for (final junk in <String>[
        'hello',
        'key/',
        'key/no-signature-separator',
        '-----BEGIN LICENSE FILE-----',
        'key/!!!.@@@',
      ]) {
        expect(
          await validator.validate(junk),
          isA<LicenseRejected>(),
          reason: junk,
        );
      }
    });

    test('a truncated key is rejected, not half-accepted', () async {
      final key = await keys.mintKey(keyPayload());
      final result = await validator.validate(
        key.substring(0, key.length - 20),
        now: duringTerm,
      );
      expect(result, isA<LicenseRejected>());
    });

    test('a tampered payload fails the signature', () async {
      // Re-encode the payload with a richer policy and keep the original
      // signature — the attack the signature exists to stop.
      final honest = await keys.mintKey(keyPayload());
      final signature = honest.substring(honest.lastIndexOf('.') + 1);
      final forgedPayload = base64Url
          .encode(
            utf8.encode(
              json.encode(keyPayload(policy: testSuiteEnterprisePolicyId)),
            ),
          )
          .replaceAll(RegExp(r'=+$'), '');

      final result = await validator.validate(
        'key/$forgedPayload.$signature',
        now: duringTerm,
      );
      expect(result, isA<LicenseRejected>());
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('a tampered signature fails', () async {
      final key = await keys.mintKey(keyPayload());
      final dot = key.lastIndexOf('.');
      final signature = key.substring(dot + 1);
      final flipped = signature.replaceRange(
        0,
        1,
        signature[0] == 'A' ? 'B' : 'A',
      );
      final result = await validator.validate(
        '${key.substring(0, dot)}.$flipped',
        now: duringTerm,
      );
      expect(result, isA<LicenseRejected>());
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('a key signed by somebody else is untrusted', () async {
      final stranger = await TestIssuerKeys.fromSeed(9);
      final key = await stranger.mintKey(keyPayload());
      final result = await validator.validate(key, now: duringTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('the right signature over the wrong account is caught', () async {
      final key = await keys.mintKey(
        keyPayload(account: 'deadbeef-0000-4000-8000-000000000009'),
      );
      final result = await validator.validate(key, now: duringTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.wrongAccount,
        reason: 'authentic bytes minted under an account we do not trust',
      );
    });

    test('an unknown policy id is reported as its own state', () async {
      final key = await keys.mintKey(
        keyPayload(policy: 'ffffffff-0000-4000-8000-00000000ffff'),
      );
      final result = await validator.validate(key, now: duringTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.unknownPolicy,
        reason: 'authentic, but this build predates the SKU',
      );
    });

    test('a licence for another product does not unlock this one', () async {
      final netcrux = CruxLicenseValidator(
        product: CruxProduct.netCrux,
        issuers: <LicenseIssuer>[issuer],
      );
      final key = await keys.mintKey(keyPayload());
      final result = await netcrux.validate(key, now: duringTerm);
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.productNotEntitled,
      );
    });
  });

  group('expiry', () {
    test('past expiry is LicenseExpired, and keeps the grant', () async {
      final key = await keys.mintKey(keyPayload());
      final result = await validator.validate(key, now: DateTime.utc(2027, 6));

      expect(result, isA<LicenseExpired>());
      expect(
        result.grant!.tier,
        LicenseTier.pro,
        reason: 'grace is decided by LicenseService, which needs the grant',
      );
      expect(
        result.tier,
        LicenseTier.openCore,
        reason: 'the validator alone never grants past expiry',
      );
      expect(result.grant!.isExpiredAt(DateTime.utc(2027, 6)), isTrue);
    });

    test('a perpetual licence never expires', () async {
      final key = await keys.mintKey(keyPayload(expiry: null));
      final result = await validator.validate(key, now: DateTime.utc(2099));
      expect(result, isA<LicenseAccepted>());
      expect(result.grant!.expiry, isNull);
      expect(result.grant!.remainingAt(DateTime.utc(2099)), isNull);
    });
  });

  group('licence files', () {
    test('resolve from embedded entitlements, not the table', () async {
      final file = await keys.mintFile(filePayload());
      final result = await validator.validate(file, now: duringTerm);

      expect(result, isA<LicenseAccepted>());
      final grant = result.grant!;
      expect(grant.tier, LicenseTier.pro);
      expect(grant.products, <CruxProduct>{CruxProduct.waveCrux});
      expect(grant.maxMachines, 5, reason: 'seat count the key cannot carry');
      expect(grant.email, 'buyer@example.com');
      expect(grant.resolvedFromEntitlements, isTrue);
    });

    test('a policy absent from the table still resolves', () async {
      // The airgap argument for licence files: they carry their own meaning,
      // so a build that predates the SKU can still honour them.
      final file = await keys.mintFile(
        filePayload(policy: 'ffffffff-0000-4000-8000-00000000ffff'),
      );
      expect(
        await validator.validate(file, now: duringTerm),
        isA<LicenseAccepted>(),
      );
    });

    test('enterprise wins when a file carries two tier codes', () async {
      final file = await keys.mintFile(
        filePayload(
          entitlements: const <String>[
            'WAVECRUX',
            'TIER_PRO',
            'TIER_ENTERPRISE',
          ],
        ),
      );
      final result = await validator.validate(file, now: duringTerm);
      expect(result.grant!.tier, LicenseTier.enterprise);
    });

    test('an encrypted licence file is refused by name', () async {
      final certificate = await _certificateOf(keys, filePayload());
      certificate['alg'] = 'aes-256-gcm+ed25519';

      final result = await validator.validate(
        _envelope(certificate),
        now: duringTerm,
      );
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.unsupportedAlgorithm,
      );
    });

    test('a tampered licence file fails the signature', () async {
      final certificate = await _certificateOf(keys, filePayload());
      certificate['enc'] = base64Url
          .encode(
            utf8.encode(
              json.encode(
                filePayload(
                  entitlements: const <String>['WAVECRUX', 'TIER_ENTERPRISE'],
                ),
              ),
            ),
          )
          .replaceAll(RegExp(r'=+$'), '');

      final result = await validator.validate(
        _envelope(certificate),
        now: duringTerm,
      );
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });
  });

  group('machine files', () {
    // A machine file is a licence file checked out against one registered
    // machine, and the fingerprint it carries is what binds it to one install.
    // The binding is the whole point: it is what makes a credential safe to
    // issue for a machine that will never reach the issuer, because the copy
    // that walks out on a USB stick resolves nowhere.
    test('resolve on the machine they were checked out for', () async {
      final file = await keys.mintMachineFile(
        machineFilePayload(fingerprint: 'fp-1'),
      );

      final validation = await validator.validate(
        file,
        now: duringTerm,
        fingerprint: 'fp-1',
      );

      expect(validation, isA<LicenseAccepted>());
      final grant = validation.grant!;
      expect(grant.tier, LicenseTier.pro);
      expect(grant.resolvedFromEntitlements, isTrue);
      expect(grant.licenseId, 'lic00000-0000-4000-8000-000000000001');
      expect(grant.expiry, DateTime.utc(2027));
      expect(grant.maxMachines, 5);
      expect(grant.email, 'buyer@example.com');
    });

    test('and nowhere else', () async {
      final file = await keys.mintMachineFile(
        machineFilePayload(fingerprint: 'fp-1'),
      );

      final validation = await validator.validate(
        file,
        now: duringTerm,
        fingerprint: 'fp-2',
      );

      expect(validation, isA<LicenseRejected>());
      expect(
        (validation as LicenseRejected).reason,
        LicenseRejection.wrongMachine,
      );
      expect(validation.grant, isNull, reason: 'nothing is half-granted');
    });

    test(
      'a caller that does not say which machine it is gets no grant',
      () async {
        // The controller always asks with the install's fingerprint. A caller
        // that validates a bound credential without one cannot be told it is
        // theirs, and a bound credential that resolved wherever the caller
        // forgot to ask would be bound to nothing.
        final file = await keys.mintMachineFile(
          machineFilePayload(fingerprint: 'fp-1'),
        );

        final validation = await validator.validate(file, now: duringTerm);

        expect(
          (validation as LicenseRejected).reason,
          LicenseRejection.wrongMachine,
        );
        expect(validation.detail, contains('no fingerprint was supplied'));
      },
    );

    test('a key and a licence file name no machine', () async {
      // The every-tier promise: keys and licence files keep resolving whoever
      // asks, with or without a fingerprint. Only a credential that names a
      // machine is held to one.
      final key = await keys.mintKey(keyPayload());
      final file = await keys.mintFile(filePayload());
      for (final fingerprint in <String?>[null, 'fp-1', 'fp-2']) {
        expect(
          await validator.validate(
            key,
            now: duringTerm,
            fingerprint: fingerprint,
          ),
          isA<LicenseAccepted>(),
          reason: 'key, fingerprint $fingerprint',
        );
        expect(
          await validator.validate(
            file,
            now: duringTerm,
            fingerprint: fingerprint,
          ),
          isA<LicenseAccepted>(),
          reason: 'licence file, fingerprint $fingerprint',
        );
      }
    });

    test('the fingerprint is read from the signed payload', () async {
      // Editing the fingerprint inside the file to match this machine breaks
      // the signature, so the binding cannot be moved by editing the file.
      final payload = machineFilePayload(fingerprint: 'fp-1');
      final file = await keys.mintMachineFile(payload);
      final certificate =
          json.decode(
                utf8.decode(
                  base64.decode(
                    file
                        .replaceAll('-----BEGIN MACHINE FILE-----', '')
                        .replaceAll('-----END MACHINE FILE-----', '')
                        .replaceAll('\n', ''),
                  ),
                ),
              )
              as Map<String, Object?>;
      (payload['data']! as Map<String, Object?>)['attributes'] =
          <String, Object?>{'fingerprint': 'fp-2'};
      certificate['enc'] = base64Url
          .encode(utf8.encode(json.encode(payload)))
          .replaceAll(RegExp(r'=+$'), '');
      final edited =
          '-----BEGIN MACHINE FILE-----\n'
          '${base64.encode(utf8.encode(json.encode(certificate)))}\n'
          '-----END MACHINE FILE-----\n';

      final validation = await validator.validate(
        edited,
        now: duringTerm,
        fingerprint: 'fp-2',
      );

      expect(
        (validation as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });

    test('a machine file issued without its licence grants nothing', () async {
      // `include=license,license.entitlements` is the issuer-side step that
      // makes the file resolvable. Without it there is no policy, no
      // entitlement and no expiry — and the answer is the one an old build
      // gives a SKU it has never heard of, which is what support will read.
      final payload = machineFilePayload(fingerprint: 'fp-1')
        ..['included'] = <Object?>[];
      final file = await keys.mintMachineFile(payload);

      final validation = await validator.validate(
        file,
        now: duringTerm,
        fingerprint: 'fp-1',
      );

      expect(
        (validation as LicenseRejected).reason,
        LicenseRejection.unknownPolicy,
      );
    });

    test(
      'the account is checked on the machine, not only the licence',
      () async {
        final file = await keys.mintMachineFile(
          machineFilePayload(
            fingerprint: 'fp-1',
            account: 'acc0acc0-0000-4000-8000-00000000beef',
          ),
        );

        final validation = await validator.validate(
          file,
          now: duringTerm,
          fingerprint: 'fp-1',
        );

        expect(
          (validation as LicenseRejected).reason,
          LicenseRejection.wrongAccount,
        );
      },
    );

    test("the key a machine file embeds is the licence's", () async {
      final key = await keys.mintKey(keyPayload());
      final envelope = parseLicenseCredential(
        await keys.mintMachineFile(machineFilePayload(key: key)),
      ).envelope!;

      expect(envelope.kind, LicenseCredentialKind.machineFile);
      expect(KeygenLicenseIssuer.embeddedLicenseKey(envelope), key);
    });
  });

  group('the issuer set is plural', () {
    // This is a firm design constraint: it
    // is what keeps self-issued EDU licences a configuration change rather
    // than surgery on the component all four products depend on.
    test('a second issuer verifies keys the first one did not sign', () async {
      final second = await TestIssuerKeys.fromSeed(11);
      final plural = CruxLicenseValidator(
        product: CruxProduct.waveCrux,
        issuers: <LicenseIssuer>[
          issuer,
          KeygenLicenseIssuer(
            accountId: testAccountId,
            verifyKey: second.verifyKey,
            policies: testPolicies,
          ),
        ],
      );

      expect(
        await plural.validate(
          await keys.mintKey(keyPayload()),
          now: duringTerm,
        ),
        isA<LicenseAccepted>(),
      );
      expect(
        await plural.validate(
          await second.mintKey(keyPayload()),
          now: duringTerm,
        ),
        isA<LicenseAccepted>(),
      );
    });

    test('an empty issuer set trusts nothing', () async {
      final none = CruxLicenseValidator(
        product: CruxProduct.waveCrux,
        issuers: const <LicenseIssuer>[],
      );
      final result = await none.validate(
        await keys.mintKey(keyPayload()),
        now: duringTerm,
      );
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });
  });

  group('the production issuer', () {
    test('carries the account id and public key the plan records', () {
      final production = KeygenLicenseIssuer.production();
      expect(production.accountId, kKeygenAccountId);
      expect(production.verifyKey, hasLength(32));
      expect(production.verifyKey, decodeHexKey(kKeygenVerifyKeyHex));
      expect(
        CruxLicenseValidator.production(product: CruxProduct.simCrux).issuers,
        hasLength(1),
      );
    });

    test('refuses a fixture key — the test keypair is not Keygen', () async {
      final production = CruxLicenseValidator.production(
        product: CruxProduct.waveCrux,
      );
      final result = await production.validate(
        await keys.mintKey(keyPayload(account: kKeygenAccountId)),
        now: duringTerm,
      );
      expect(
        (result as LicenseRejected).reason,
        LicenseRejection.untrustedIssuer,
      );
    });
  });
}

/// Mint a licence file and hand back its decoded certificate, so a test can
/// corrupt one field and re-envelope it.
Future<Map<String, Object?>> _certificateOf(
  TestIssuerKeys keys,
  Map<String, Object?> payload,
) async {
  final file = await keys.mintFile(payload);
  final body = file
      .split('\n')
      .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
      .join();
  return json.decode(utf8.decode(base64.decode(body))) as Map<String, Object?>;
}

String _envelope(Map<String, Object?> certificate) =>
    '-----BEGIN LICENSE FILE-----\n'
    '${base64.encode(utf8.encode(json.encode(certificate)))}\n'
    '-----END LICENSE FILE-----';
