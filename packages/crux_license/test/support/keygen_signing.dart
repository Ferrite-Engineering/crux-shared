// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

import 'license_fixtures.dart';

/// The `Date` every fake issuer answer carries. Fixed, because nothing under
/// test reads it as a clock — it is signed over, and that is all.
const String fakeIssuerDate = 'Mon, 21 Sep 2026 13:12:59 GMT';

/// A fake issuer's answer, signed the way the real one signs every response.
///
/// Keygen signs each response over the request target, the host, the `Date`
/// header and a SHA-256 digest of the raw body, and sends the signature in a
/// `Keygen-Signature` header. The client refuses a validate answer that does
/// not carry a signature its account key verifies, so a fake that wants its
/// answer *used* has to sign it with the throwaway key the validator under
/// test trusts. The format below is the one the live API produces, verified
/// against it with the account's real public key.
http.StreamedResponse signedIssuerResponse({
  required TestIssuerKeys keys,
  required http.BaseRequest request,
  required Map<String, Object?> body,
  int status = 200,
  String? date,
}) {
  final bytes = utf8.encode(json.encode(body));
  return signedIssuerBytes(
    keys: keys,
    request: request,
    bytes: bytes,
    status: status,
    date: date,
  );
}

/// [signedIssuerResponse] over raw [bytes], for a body that is deliberately
/// not JSON.
http.StreamedResponse signedIssuerBytes({
  required TestIssuerKeys keys,
  required http.BaseRequest request,
  required List<int> bytes,
  int status = 200,
  String? date,
  String? signingOverride,
}) {
  final url = request.url;
  final target =
      '${request.method.toLowerCase()} ${url.path}'
      '${url.hasQuery ? '?${url.query}' : ''}';
  final digest = 'sha-256=${base64.encode(sha256.convert(bytes).bytes)}';
  final when = date ?? fakeIssuerDate;
  final signing =
      signingOverride ??
      '(request-target): $target\nhost: ${url.host}\ndate: $when\n'
          'digest: $digest';
  final signature = base64.encode(keys.signBytes(utf8.encode(signing)));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    headers: <String, String>{
      'content-type': 'application/vnd.api+json; charset=utf-8',
      'date': when,
      'digest': digest,
      'keygen-signature':
          'keyid="$testAccountId", algorithm="ed25519", '
          'signature="$signature", '
          'headers="(request-target) host date digest"',
    },
  );
}

/// An unsigned answer: what a proxy that rewrote the body, or an issuer whose
/// signing changed shape, would look like to the client.
http.StreamedResponse unsignedIssuerResponse(
  Map<String, Object?> body, {
  int status = 200,
}) => http.StreamedResponse(
  Stream<List<int>>.value(utf8.encode(json.encode(body))),
  status,
);

/// A client answering every call with one signed JSON [body].
http.Client signedJsonClient(
  TestIssuerKeys keys,
  Map<String, Object?> body, {
  int status = 200,
}) => stubClient(
  (request) => signedIssuerResponse(
    keys: keys,
    request: request,
    body: body,
    status: status,
  ),
);

/// A client that answers with whatever [answer] returns.
http.Client stubClient(
  http.StreamedResponse Function(http.BaseRequest request) answer,
) => _StubClient(answer);

class _StubClient extends http.BaseClient {
  _StubClient(this._answer);

  final http.StreamedResponse Function(http.BaseRequest request) _answer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _answer(request);
}
