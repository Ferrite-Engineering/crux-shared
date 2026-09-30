// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_policy/crux_policy.dart';
import 'package:test/test.dart';

/// Parsing the organization's public key file.
///
/// Pure, so it also runs under `dart test -p chrome` with the rest of the
/// package — the parser is reachable from a web build even though the file
/// never is.
void main() {
  final key = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
  final keyB64 = base64.encode(key);
  final keyHex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  const spki = <int>[
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00, //
  ];

  group('accepted encodings', () {
    test('the base64 line crux-policy sign prints', () {
      final parsed = PolicyPublicKey.parse('$keyB64\n');
      expect(parsed.status, PolicyKeyStatus.configured);
      expect(parsed.bytes, key);
    });

    test('url-safe base64 without padding', () {
      final urlSafe = keyB64
          .replaceAll('+', '-')
          .replaceAll('/', '_')
          .replaceAll('=', '');
      expect(PolicyPublicKey.parse(urlSafe).bytes, key);
    });

    test('64 hex characters, either case', () {
      expect(PolicyPublicKey.parse(keyHex).bytes, key);
      expect(PolicyPublicKey.parse(keyHex.toUpperCase()).bytes, key);
    });

    test('a PEM PUBLIC KEY block, as openssl writes it', () {
      final body = base64.encode([...spki, ...key]);
      final pem =
          '-----BEGIN PUBLIC KEY-----\n'
          '${body.substring(0, 60)}\n${body.substring(60)}\n'
          '-----END PUBLIC KEY-----\n';
      final parsed = PolicyPublicKey.parse(pem);
      expect(parsed.status, PolicyKeyStatus.configured);
      expect(parsed.bytes, key);
    });

    test('the bare SubjectPublicKeyInfo bytes in base64', () {
      expect(
        PolicyPublicKey.parse(base64.encode([...spki, ...key])).bytes,
        key,
      );
    });

    test('comments, blank lines and surrounding whitespace are ignored', () {
      final text = '\n# Example Semiconductor policy key\n\n  $keyB64  \n\n';
      expect(PolicyPublicKey.parse(text).bytes, key);
    });
  });

  group('everything else is malformed, and nothing throws', () {
    for (final (label, text) in <(String, String)>[
      ('empty', ''),
      ('only a comment', '# nothing here\n'),
      ('not base64', 'this is not a key'),
      (
        'an OpenSSH line',
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx ops@example',
      ),
      ('31 bytes', base64.encode(key.sublist(1))),
      ('33 bytes', base64.encode([...key, 0])),
      ('63 hex chars', keyHex.substring(1)),
      ('an RSA SPKI', base64.encode([0x30, 0x82, 0x01, 0x22, ...key, ...key])),
      (
        'a PEM block with the wrong OID',
        () {
          final wrong = [...spki]..[7] = 0x66;
          return '-----BEGIN PUBLIC KEY-----\n'
              '${base64.encode([...wrong, ...key])}\n'
              '-----END PUBLIC KEY-----';
        }(),
      ),
    ]) {
      test(label, () {
        late PolicyPublicKey parsed;
        expect(() => parsed = PolicyPublicKey.parse(text), returnsNormally);
        expect(parsed.status, PolicyKeyStatus.malformed);
        expect(parsed.bytes, isNull);
      });
    }
  });

  group('PolicyPublicKey.of', () {
    test('null is none', () {
      expect(PolicyPublicKey.of(null).status, PolicyKeyStatus.none);
    });

    test('32 bytes is configured, and the bytes cannot be edited', () {
      final parsed = PolicyPublicKey.of(key);
      expect(parsed.status, PolicyKeyStatus.configured);
      expect(() => parsed.bytes![0] = 1, throwsUnsupportedError);
    });

    test('any other length is malformed rather than thrown', () {
      expect(PolicyPublicKey.of(const []).status, PolicyKeyStatus.malformed);
      expect(
        PolicyPublicKey.of(List.filled(64, 0)).status,
        PolicyKeyStatus.malformed,
      );
    });
  });

  test('the file name is the one the docs and the installer agree on', () {
    expect(kPolicyPublicKeyFileName, 'crux-policy.pub');
  });
}
