// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// The issuer's signature over its answers, and what the client does with it.
///
/// The first group is the one that matters most and the only one that could
/// not be written from a fixture: a validate-key response captured from the
/// live API, headers and body verbatim, checked against the account's public
/// key with the suite's own verifier. The request used a key that does not
/// exist, so the body says `NOT_FOUND` and nothing in it is secret. If the
/// issuer ever changes what it signs or how, this is the test that says so —
/// and the consequence would be every phone-home reading as offline, which is
/// what the fixture-based tests below cannot notice on their own.
void main() {
  group('a response captured from the live API', () {
    // Verbatim from `api.keygen.sh`: the `Date` and `Keygen-Signature`
    // headers and the 157-byte body of a validate-key answer.
    const date = 'Mon, 21 Sep 2026 13:13:39 GMT';
    const signature =
        'BDDWn4z0O6DJuhJI5VIkri1sQ4+HwoIGPcuYBBFLZrCEesWXRNAINeWD3I4rZeBO8KIR'
        'DpjvDV+lufYrurerCQ==';
    const body =
        '{"data":null,"meta":{"ts":"2026-09-21T13:13:39.990Z","valid":false,'
        // The body is compact JSON, so the pieces join with no whitespace on
        // purpose: one added byte and the digest no longer matches.
        // ignore: missing_whitespace_between_adjacent_strings
        '"detail":"does not exist","code":"NOT_FOUND",'
        '"scope":{"fingerprint":"probe-fingerprint"}}}';
    const target =
        'post /v1/accounts/$kKeygenAccountId/licenses/actions/validate-key';

    const live = KeygenAttestation(
      requestTarget: target,
      host: 'api.keygen.sh',
      date: date,
      body: body,
      signature: signature,
    );

    test('verifies with the compiled-in account key', () {
      expect(
        live.digest,
        'sha-256=HrtVo7ff/5xCP52B3OnZEHxS1XBBYaRI8POjChq0t6s=',
        reason: 'the Digest header the issuer sent alongside',
      );
      expect(live.verify(decodeHexKey(kKeygenVerifyKeyHex)), isTrue);
    });

    test('is a validate answer to the production client', () {
      final client = KeygenLicenseClient(client: http.Client());
      addTearDown(client.close);
      expect(client.attestsValidation(live), isTrue);

      final answer = KeygenValidation.fromBody(
        live.decodedBody!,
        attestation: live,
      );
      expect(answer.code, KeygenValidationCode.notFound);
      expect(answer.scopeFingerprint, 'probe-fingerprint');
      expect(answer.attested, isTrue);
    });

    test("one changed byte of body and it is nobody's answer", () {
      final edited = KeygenAttestation(
        requestTarget: target,
        host: 'api.keygen.sh',
        date: date,
        body: body.replaceFirst('"valid":false', '"valid":true'),
        signature: signature,
      );
      expect(edited.verify(decodeHexKey(kKeygenVerifyKeyHex)), isFalse);
    });

    test('a fixture key does not verify it', () async {
      final keys = await TestIssuerKeys.fromSeed(7);
      expect(live.verify(keys.verifyKey), isFalse);
    });
  });

  group('the client', () {
    late TestIssuerKeys keys;
    setUpAll(() async => keys = await TestIssuerKeys.fromSeed(7));

    KeygenLicenseClient clientOver(http.Client http) => KeygenLicenseClient(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      client: http,
    );

    final valid = <String, Object?>{
      'meta': <String, Object?>{'valid': true, 'code': 'VALID'},
      'data': <String, Object?>{
        'id': 'lic-1',
        'attributes': <String, Object?>{'expiry': '2027-01-01T00:00:00Z'},
        'relationships': <String, Object?>{
          'machines': <String, Object?>{
            'meta': <String, Object?>{'count': 2},
          },
        },
      },
    };

    test('a signed answer is attested and carries its signature', () async {
      final client = clientOver(signedJsonClient(keys, valid));
      addTearDown(client.close);

      final answer = await client.validateKey('key/x', fingerprint: 'f-1');

      expect(answer.attested, isTrue);
      expect(answer.code, KeygenValidationCode.valid);
      expect(answer.expiry, DateTime.utc(2027));
      expect(answer.machineCount, 2, reason: 'read from the relationship');
      expect(client.attestsValidation(answer.attestation!), isTrue);
    });

    test('the attestation survives the store', () async {
      final client = clientOver(signedJsonClient(keys, valid));
      addTearDown(client.close);
      final answer = await client.validateKey('key/x');

      final stored = json.encode(answer.attestation!.toJson());
      final back = KeygenAttestation.fromJson(json.decode(stored));

      expect(back, isNotNull);
      expect(client.attestsValidation(back!), isTrue);
      expect(back.decodedBody, answer.attestation!.decodedBody);
    });

    test('an unsigned answer is unreached', () async {
      final client = clientOver(
        stubClient((_) => unsignedIssuerResponse(valid)),
      );
      addTearDown(client.close);

      final answer = await client.validateKey('key/x');

      expect(answer.attested, isFalse);
      expect(answer.code, KeygenValidationCode.unknown);
      expect(answer.valid, isFalse);
    });

    test('a signature by another key is unreached', () async {
      final other = await TestIssuerKeys.fromSeed(8);
      final client = clientOver(signedJsonClient(other, valid));
      addTearDown(client.close);

      expect((await client.validateKey('key/x')).attested, isFalse);
    });

    test('a signature over a different body is unreached', () async {
      // The digest is recomputed from the body, never read from a header, so
      // a body swapped under a genuine signature is caught.
      final client = clientOver(
        stubClient((request) {
          final genuine = signedIssuerResponse(
            keys: keys,
            request: request,
            body: <String, Object?>{
              'meta': <String, Object?>{'valid': false, 'code': 'EXPIRED'},
            },
          );
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(json.encode(valid))),
            200,
            headers: genuine.headers,
          );
        }),
      );
      addTearDown(client.close);

      expect((await client.validateKey('key/x')).attested, isFalse);
    });

    test('a signed answer to some other request is not a validation', () {
      // A genuinely signed response — say a licence read — replayed as a
      // validate answer. Same key, same host, wrong target.
      final request = http.Request(
        'GET',
        Uri.parse('https://api.keygen.sh/v1/accounts/$testAccountId/licenses'),
      );
      final signed = signedIssuerResponse(
        keys: keys,
        request: request,
        body: valid,
      );
      final attestation = KeygenAttestation.fromResponse(
        method: 'GET',
        url: request.url,
        headers: signed.headers,
        bodyBytes: utf8.encode(json.encode(valid)),
      )!;
      final client = clientOver(http.Client());
      addTearDown(client.close);

      expect(attestation.verify(keys.verifyKey), isTrue);
      expect(client.attestsValidation(attestation), isFalse);
    });

    test('a signed answer from another host is not a validation', () {
      final request = http.Request(
        'POST',
        Uri.parse(
          'https://example.test/v1/accounts/$testAccountId'
          '/licenses/actions/validate-key',
        ),
      );
      final signed = signedIssuerResponse(
        keys: keys,
        request: request,
        body: valid,
      );
      final attestation = KeygenAttestation.fromResponse(
        method: 'POST',
        url: request.url,
        headers: signed.headers,
        bodyBytes: utf8.encode(json.encode(valid)),
      )!;
      final client = clientOver(http.Client());
      addTearDown(client.close);

      expect(client.attestsValidation(attestation), isFalse);
    });

    test('machine calls are answered whether or not they are signed', () async {
      // Only the validate answer is persisted and only it can extend a
      // licence; a registration can only take a seat, a release only clear
      // local state. Requiring a signature there would add nothing.
      final client = clientOver(
        stubClient(
          (_) => unsignedIssuerResponse(<String, Object?>{
            'data': <String, Object?>{'type': 'machines', 'id': 'm-1'},
          }, status: 201),
        ),
      );
      addTearDown(client.close);

      final result = await client.activateMachine(
        key: 'key/x',
        licenseId: 'lic-1',
        fingerprint: 'f-1',
        name: 'lab',
        platform: 'macos',
      );

      expect(result.outcome, KeygenMachineOutcome.ok);
      expect(result.machineId, 'm-1');
    });
  });

  group('reading an attestation back is total', () {
    test('anything that is not the five strings is null', () {
      for (final junk in <Object?>[
        null,
        'text',
        <Object?>[],
        <String, Object?>{},
        <String, Object?>{'requestTarget': 1},
        <String, Object?>{
          'requestTarget': 'post /x',
          'host': 'h',
          'date': 'd',
          'body': '{}',
        },
      ]) {
        expect(KeygenAttestation.fromJson(junk), isNull, reason: '$junk');
      }
    });

    test('a signature that is not base64 verifies as false, not thrown', () {
      const attestation = KeygenAttestation(
        requestTarget: 'post /x',
        host: 'h',
        date: 'd',
        body: '{}',
        signature: '!!not base64!!',
      );
      expect(attestation.verify(List<int>.filled(32, 0)), isFalse);
    });

    test('a body that is not JSON decodes to null', () {
      const attestation = KeygenAttestation(
        requestTarget: 'post /x',
        host: 'h',
        date: 'd',
        body: 'not json {',
        signature: '',
      );
      expect(attestation.decodedBody, isNull);
    });

    test('a response without the signature header has no attestation', () {
      expect(
        KeygenAttestation.fromResponse(
          method: 'POST',
          url: Uri.parse('https://api.keygen.sh/x'),
          headers: const <String, String>{'date': 'd'},
          bodyBytes: utf8.encode('{}'),
        ),
        isNull,
      );
    });
  });
}
