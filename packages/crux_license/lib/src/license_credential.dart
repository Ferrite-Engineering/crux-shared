// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/src/license_validation.dart';
import 'package:meta/meta.dart';

/// The credential formats this build can parse.
enum LicenseCredentialKind {
  /// A Keygen cryptographic licence key: `key/<payload>.<signature>`.
  ///
  /// This is what a customer receives by email and what they paste. It is
  /// ~700 characters because it carries its own signed dataset — which is
  /// exactly what buys offline verification.
  licenseKey,

  /// A Keygen licence file: `-----BEGIN LICENSE FILE----- … -----END …`.
  ///
  /// Downloaded rather than emailed: it embeds the whole licence object,
  /// entitlements included, so it resolves without the compiled policy table
  /// and honours a SKU the build predates. It names no machine, so it is a
  /// bearer credential — anyone holding it can import it — and its seat is
  /// counted only when the machine can reach the issuer.
  licenseFile,

  /// A Keygen machine file: `-----BEGIN MACHINE FILE----- … -----END …`.
  ///
  /// The artefact of offline activation. Checked out against one registered
  /// machine, it carries that machine's fingerprint inside the signed
  /// payload, with the licence and its entitlements included beside it. It
  /// resolves only on the install whose fingerprint it names, which is what
  /// makes it safe to issue for a machine that will never reach the issuer:
  /// copying it elsewhere yields nothing.
  machineFile;

  /// The prefix Keygen prepends to the encoded payload before signing.
  String get signingPrefix => switch (this) {
    LicenseCredentialKind.licenseKey => 'key/',
    LicenseCredentialKind.licenseFile => 'license/',
    LicenseCredentialKind.machineFile => 'machine/',
  };
}

/// A parsed, not-yet-verified credential: the bytes that were signed, the
/// signature over them, and the decoded payload.
@immutable
class LicenseEnvelope {
  /// Create an envelope.
  const LicenseEnvelope({
    required this.kind,
    required this.signedMessage,
    required this.signature,
    required this.payload,
  });

  /// Which format this came from.
  final LicenseCredentialKind kind;

  /// The exact bytes the issuer signed — the ASCII of
  /// `<prefix><encoded payload>`, not the decoded payload. Signing the encoded
  /// form is what makes the check independent of JSON canonicalisation.
  final List<int> signedMessage;

  /// Raw 64-byte Ed25519 signature.
  final List<int> signature;

  /// The decoded payload object.
  final Map<String, Object?> payload;
}

/// Outcome of [parseLicenseCredential]: an envelope, or the reason there is
/// none.
@immutable
class LicenseEnvelopeParse {
  /// A successful parse.
  const LicenseEnvelopeParse.ok(LicenseEnvelope this.envelope)
    : rejection = null,
      detail = '';

  /// A failed parse.
  const LicenseEnvelopeParse.failed(
    LicenseRejection this.rejection, [
    this.detail = '',
  ]) : envelope = null;

  /// The envelope, when parsing succeeded.
  final LicenseEnvelope? envelope;

  /// Why parsing failed, when it did.
  final LicenseRejection? rejection;

  /// Developer-facing detail for logs.
  final String detail;
}

const String _fileBegin = '-----BEGIN LICENSE FILE-----';
const String _fileEnd = '-----END LICENSE FILE-----';
const String _machineBegin = '-----BEGIN MACHINE FILE-----';
const String _machineEnd = '-----END MACHINE FILE-----';

/// Parse [raw] into a [LicenseEnvelope] without verifying anything.
///
/// Total by construction: every path returns a [LicenseEnvelopeParse], and no
/// input reaches a `throw`. Callers paste arbitrary text into this — a
/// truncated key, a whole email, a PDF's worth of bytes — and the UI needs a
/// sentence back, not a crash.
LicenseEnvelopeParse parseLicenseCredential(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const LicenseEnvelopeParse.failed(
      LicenseRejection.malformed,
      'empty',
    );
  }
  if (text.startsWith(_fileBegin)) {
    return _parseFile(
      text,
      kind: LicenseCredentialKind.licenseFile,
      begin: _fileBegin,
      end: _fileEnd,
    );
  }
  if (text.startsWith(_machineBegin)) {
    return _parseFile(
      text,
      kind: LicenseCredentialKind.machineFile,
      begin: _machineBegin,
      end: _machineEnd,
    );
  }
  if (text.startsWith(LicenseCredentialKind.licenseKey.signingPrefix)) {
    return _parseLicenseKey(text);
  }
  return const LicenseEnvelopeParse.failed(
    LicenseRejection.malformed,
    'no recognised credential prefix',
  );
}

LicenseEnvelopeParse _parseLicenseKey(String text) {
  // `key/<base64 dataset>.<base64 signature>`. The dataset itself is base64,
  // which never contains a `.`, so the LAST dot is the separator either way —
  // but split from the right so a future payload change cannot break this.
  final dot = text.lastIndexOf('.');
  if (dot < 0) {
    return const LicenseEnvelopeParse.failed(
      LicenseRejection.malformed,
      'licence key has no signature separator',
    );
  }
  final signed = text.substring(0, dot);
  final encoded = signed.substring(
    LicenseCredentialKind.licenseKey.signingPrefix.length,
  );
  final signature = _decodeBase64(text.substring(dot + 1));
  if (signature == null || signature.length != 64) {
    return const LicenseEnvelopeParse.failed(
      LicenseRejection.malformed,
      'signature is not 64 bytes of base64',
    );
  }
  final payload = _decodeJsonObject(_decodeBase64(encoded));
  if (payload == null) {
    return const LicenseEnvelopeParse.failed(
      LicenseRejection.undecodablePayload,
      'licence key payload is not a JSON object',
    );
  }
  return LicenseEnvelopeParse.ok(
    LicenseEnvelope(
      kind: LicenseCredentialKind.licenseKey,
      signedMessage: utf8.encode(signed),
      signature: signature,
      payload: payload,
    ),
  );
}

/// Licence files and machine files share one certificate format — a base64
/// body holding `{enc, sig, alg}` — and differ in their markers and in the
/// prefix the signature was taken over.
LicenseEnvelopeParse _parseFile(
  String text, {
  required LicenseCredentialKind kind,
  required String begin,
  required String end,
}) {
  final noun = kind == LicenseCredentialKind.machineFile
      ? 'machine file'
      : 'licence file';
  // Search from the end of the BEGIN marker, never from 0. Both markers end
  // in five dashes, so `-----BEGIN LICENSE FILE-----END LICENSE FILE-----`
  // — a 49-character paste of a file with its body deleted — matches the END
  // marker at index 23, five characters INSIDE the BEGIN marker. Searching
  // from 0 there gave `substring(28, 23)`, which throws RangeError: an Error,
  // not an Exception, so it escaped every `on Exception` up the activation
  // path. Starting the search at the body makes `end` either -1 or a valid
  // substring bound by construction.
  final endAt = text.indexOf(end, begin.length);
  if (endAt < 0) {
    return LicenseEnvelopeParse.failed(
      LicenseRejection.malformed,
      '$noun has no END marker',
    );
  }
  final body = _decodeBase64(text.substring(begin.length, endAt));
  final certificate = _decodeJsonObject(body);
  if (certificate == null) {
    return LicenseEnvelopeParse.failed(
      LicenseRejection.undecodablePayload,
      '$noun body is not a JSON object',
    );
  }
  final alg = certificate['alg'];
  if (alg != 'base64+ed25519') {
    // `aes-256-gcm+ed25519` files are encrypted with the licence key as the
    // secret. They are a legitimate Keygen format and a legitimate future
    // feature; they are not something a paste alone can open.
    return LicenseEnvelopeParse.failed(
      LicenseRejection.unsupportedAlgorithm,
      '$noun alg is ${alg ?? 'absent'}',
    );
  }
  final enc = certificate['enc'];
  final sig = certificate['sig'];
  if (enc is! String || sig is! String) {
    return LicenseEnvelopeParse.failed(
      LicenseRejection.malformed,
      '$noun is missing enc or sig',
    );
  }
  final signature = _decodeBase64(sig);
  if (signature == null || signature.length != 64) {
    return LicenseEnvelopeParse.failed(
      LicenseRejection.malformed,
      '$noun signature is not 64 bytes of base64',
    );
  }
  final payload = _decodeJsonObject(_decodeBase64(enc));
  if (payload == null) {
    return LicenseEnvelopeParse.failed(
      LicenseRejection.undecodablePayload,
      '$noun payload is not a JSON object',
    );
  }
  return LicenseEnvelopeParse.ok(
    LicenseEnvelope(
      kind: kind,
      signedMessage: utf8.encode('${kind.signingPrefix}$enc'),
      signature: signature,
      payload: payload,
    ),
  );
}

/// Decode base64 in either alphabet, with or without padding, ignoring any
/// whitespace. Returns `null` rather than throwing on anything else.
///
/// Tolerant on purpose. A credential travels through email clients, terminal
/// copy-paste and PDF purchase orders; rejecting a key because it arrived
/// wrapped at 64 columns would be a support ticket, not a security property.
/// The signature check is what makes tolerance safe.
List<int>? _decodeBase64(String input) {
  var text = input.replaceAll(RegExp(r'\s'), '');
  if (text.isEmpty) return null;
  text = text.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = text.length % 4;
  if (remainder == 1) return null;
  if (remainder != 0) {
    text = text.padRight(text.length + (4 - remainder), '=');
  }
  try {
    return base64.decode(text);
  } on FormatException {
    return null;
  }
}

Map<String, Object?>? _decodeJsonObject(List<int>? bytes) {
  if (bytes == null) return null;
  try {
    final decoded = json.decode(utf8.decode(bytes));
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
