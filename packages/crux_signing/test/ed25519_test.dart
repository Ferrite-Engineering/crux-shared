// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_signing/crux_signing.dart';
import 'package:test/test.dart';

import 'support/ed25519_sign.dart';

/// The hand-written Ed25519 verifier, against RFC 8032's own vectors.
///
/// Hand-written cryptography earns this much scrutiny. The verifier exists at
/// all because `package:cryptography` would put a cipher in every product and
/// break the suite's export-control position (see the doc comment on
/// `lib/src/ed25519.dart`), so the trade made there is paid for here: the
/// published vectors, then the failure modes a naive implementation accepts.
void main() {
  group('RFC 8032 §7.1 test vectors', () {
    const vectors = <(String, String, String)>[
      // (public key, message, signature) — all hex.
      (
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        '',
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e0652249015'
            '55fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe2465514143'
            '8e7a100b',
      ),
      (
        '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        '72',
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69'
            'da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d2916'
            '12bb0c00',
      ),
      (
        'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025',
        'af82',
        '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3'
            'ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027bece'
            'ea1ec40a',
      ),
    ];

    for (final (index, vector) in vectors.indexed) {
      test('vector ${index + 1} verifies', () {
        final (publicKey, message, signature) = vector;
        expect(
          ed25519Verify(
            message: _hex(message),
            signature: _hex(signature),
            publicKey: _hex(publicKey),
          ),
          isTrue,
        );
      });

      test('vector ${index + 1} fails under a one-bit change', () {
        final (publicKey, message, signature) = vector;
        final tampered = _hex(signature);
        tampered[0] ^= 1;
        expect(
          ed25519Verify(
            message: _hex(message),
            signature: tampered,
            publicKey: _hex(publicKey),
          ),
          isFalse,
        );

        final otherMessage = <int>[..._hex(message), 0];
        expect(
          ed25519Verify(
            message: otherMessage,
            signature: _hex(signature),
            publicKey: _hex(publicKey),
          ),
          isFalse,
          reason: 'a signature must not carry over to a longer message',
        );
      });
    }
  });

  group('malformed input is refused, never thrown on', () {
    final pair = TestEd25519KeyPair.fromSeed(List<int>.filled(32, 3));
    final message = utf8.encode('key/whatever');
    final signature = pair.sign(message);

    test('the honest case verifies, so the negatives are not vacuous', () {
      expect(
        ed25519Verify(
          message: message,
          signature: signature,
          publicKey: pair.publicKey,
        ),
        isTrue,
      );
    });

    test('wrong lengths', () {
      expect(
        ed25519Verify(
          message: message,
          signature: signature.sublist(0, 63),
          publicKey: pair.publicKey,
        ),
        isFalse,
      );
      expect(
        ed25519Verify(
          message: message,
          signature: signature,
          publicKey: pair.publicKey.sublist(0, 31),
        ),
        isFalse,
      );
      expect(
        ed25519Verify(
          message: message,
          signature: const <int>[],
          publicKey: const <int>[],
        ),
        isFalse,
      );
    });

    test('a public key that is not a point on the curve', () {
      // y = 2 has no corresponding x, so decompression must fail rather than
      // produce a garbage point that some scalar happens to satisfy.
      final notAPoint = List<int>.filled(32, 0)..[0] = 2;
      expect(
        ed25519Verify(
          message: message,
          signature: signature,
          publicKey: notAPoint,
        ),
        isFalse,
      );
    });

    test('a non-canonical S is refused — malleability', () {
      // S + L is an equivalent scalar. Accepting it would mean one licence
      // key has an unbounded family of equally valid spellings, and "is this
      // the same key" stops being answerable by comparing bytes.
      final malleable = List<int>.from(signature);
      var carry = 0;
      const order = <int>[
        0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, //
        0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
      ];
      for (var i = 0; i < 32; i++) {
        final sum = malleable[32 + i] + order[i] + carry;
        malleable[32 + i] = sum & 0xff;
        carry = sum >> 8;
      }
      expect(
        ed25519Verify(
          message: message,
          signature: malleable,
          publicKey: pair.publicKey,
        ),
        isFalse,
      );
    });

    test('a signature from a different key', () {
      final other = TestEd25519KeyPair.fromSeed(List<int>.filled(32, 4));
      expect(
        ed25519Verify(
          message: message,
          signature: other.sign(message),
          publicKey: pair.publicKey,
        ),
        isFalse,
      );
    });

    test('an all-zero signature over an all-zero key', () {
      expect(
        ed25519Verify(
          message: message,
          signature: List<int>.filled(64, 0),
          publicKey: List<int>.filled(32, 0),
        ),
        isFalse,
        reason: 'the identity point must not verify arbitrary messages',
      );
    });
  });

  test('the test signer agrees with RFC 8032 §7.1', () {
    // The fixtures the whole validator suite rests on are minted by
    // test/support/ed25519_sign.dart. If that signer were wrong, every
    // "valid key" test would be testing agreement between two bugs.
    const seed =
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
    const expectedPublic =
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
    const expectedSignature =
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e0652249015'
        '55fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

    final pair = TestEd25519KeyPair.fromSeed(_hex(seed));
    expect(_toHex(pair.publicKey), expectedPublic);
    expect(_toHex(pair.sign(const <int>[])), expectedSignature);
  });
}

List<int> _hex(String value) => <int>[
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
