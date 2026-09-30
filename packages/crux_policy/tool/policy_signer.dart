// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Ed25519 **signing**, for the `crux-policy` CLI only.
///
/// ### Why this file is in `tool/` and not in `lib/`
///
/// `crux_signing` verifies and cannot sign, deliberately: **no product build
/// may contain signing code**, because that is what keeps open core free of
/// non-exempt encryption for export control, and every store listing's
/// `ITSAppUsesNonExemptEncryption=false` true. The `sign` subcommand needs a
/// real signer, so the question is where it can live without reaching a
/// product.
///
/// The answer: here, reachable only from `bin/`. It is **not exported from
/// `package:crux_policy/crux_policy.dart`**, and every product imports exactly
/// that barrel — so nothing a product can name can reach this. The proof is
/// mechanical rather than a promise: the export-control guard resolves each
/// product's real dependency closure, and this would fail it.
///
/// A separate signing package taken as a `dev_dependency` was the other
/// candidate and is worse. It would put a signer in the resolved dev closure
/// of every consumer of this package, and "dev dependencies do not ship" is a
/// claim about a build system rather than a fact about the source tree.
///
/// The key here is the **organization's own**, supplied on the command line.
/// Ferrite holds no policy signing key and must never appear to.
///
/// RFC 8032 §5.1.6. Not constant-time and not hardened: it runs on an
/// administrator's own machine, on a key they already hold.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crux_policy/crux_policy.dart';
import 'package:crypto/crypto.dart' show sha512;

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _l =
    (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');
final BigInt _d = (BigInt.from(-121665) * _inverse(BigInt.from(121666))) % _p;
final BigInt _sqrtMinusOne = BigInt.two.modPow((_p - BigInt.one) >> 2, _p);

/// A throwaway Ed25519 keypair derived from a 32-byte seed.
class PolicyEd25519KeyPair {
  PolicyEd25519KeyPair._(this.seed, this.publicKey, this._scalar, this._prefix);

  /// Derive a keypair from a 32-byte [seed].
  factory PolicyEd25519KeyPair.fromSeed(List<int> seed) {
    if (seed.length != 32) {
      throw ArgumentError.value(seed, 'seed', 'must be 32 bytes');
    }
    final h = sha512.convert(seed).bytes;
    final clamped = Uint8List.fromList(h.sublist(0, 32))
      ..[0] &= 248
      ..[31] &= 127
      ..[31] |= 64;
    final scalar = _littleEndian(clamped);
    final publicKey = _encodePoint(_scalarMult(_base, scalar));
    return PolicyEd25519KeyPair._(
      List<int>.unmodifiable(seed),
      publicKey,
      scalar,
      h.sublist(32),
    );
  }

  /// The 32-byte seed this pair was derived from.
  final List<int> seed;

  /// The 32-byte public key, which is what an issuer is configured with.
  final List<int> publicKey;

  final BigInt _scalar;
  final List<int> _prefix;

  /// Sign [message], returning the 64-byte signature.
  List<int> sign(List<int> message) {
    final r =
        _littleEndian(sha512.convert(<int>[..._prefix, ...message]).bytes) % _l;
    final rPoint = _encodePoint(_scalarMult(_base, r));
    final k =
        _littleEndian(
          sha512.convert(<int>[...rPoint, ...publicKey, ...message]).bytes,
        ) %
        _l;
    final s = (r + k * _scalar) % _l;
    return <int>[...rPoint, ..._encodeScalar(s)];
  }
}

class _Point {
  const _Point(this.x, this.y, this.z, this.t);
  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;
}

final _Point _identity = _Point(
  BigInt.zero,
  BigInt.one,
  BigInt.one,
  BigInt.zero,
);

final _Point _base = () {
  final y = BigInt.from(4) * _inverse(BigInt.from(5)) % _p;
  final x = _recoverX(y);
  return _Point(x, y, BigInt.one, x * y % _p);
}();

BigInt _inverse(BigInt value) => value.modPow(_p - BigInt.two, _p);

BigInt _littleEndian(List<int> bytes) {
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

BigInt _recoverX(BigInt y) {
  final y2 = y * y % _p;
  final u = (y2 - BigInt.one) % _p;
  final v = (_d * y2 + BigInt.one) % _p;
  final v3 = v * v % _p * v % _p;
  final v7 = v3 * v3 % _p * v % _p;
  var x = u * v3 % _p * (u * v7).modPow((_p - BigInt.from(5)) >> 3, _p) % _p;
  if (v * x % _p * x % _p != u % _p) x = x * _sqrtMinusOne % _p;
  if (x.isOdd) x = _p - x;
  return x;
}

List<int> _encodeScalar(BigInt value) {
  final bytes = Uint8List(32);
  var remaining = value;
  for (var i = 0; i < 32; i++) {
    bytes[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return bytes;
}

List<int> _encodePoint(_Point point) {
  final zInverse = _inverse(point.z);
  final x = point.x * zInverse % _p;
  final y = point.y * zInverse % _p;
  final bytes = Uint8List.fromList(_encodeScalar(y));
  if (x.isOdd) bytes[31] |= 0x80;
  return bytes;
}

_Point _add(_Point a, _Point b) {
  final aa = (a.y - a.x) * (b.y - b.x) % _p;
  final bb = (a.y + a.x) * (b.y + b.x) % _p;
  final cc = BigInt.two * a.t % _p * b.t % _p * _d % _p;
  final dd = BigInt.two * a.z % _p * b.z % _p;
  final e = (bb - aa) % _p;
  final f = (dd - cc) % _p;
  final g = (dd + cc) % _p;
  final h = (bb + aa) % _p;
  return _Point(e * f % _p, g * h % _p, f * g % _p, e * h % _p);
}

_Point _scalarMult(_Point point, BigInt scalar) {
  var result = _identity;
  var addend = point;
  var remaining = scalar;
  while (remaining > BigInt.zero) {
    if (remaining.isOdd) result = _add(result, addend);
    addend = _add(addend, addend);
    remaining >>= 1;
  }
  return result;
}

/// Sign [document] with the organization's Ed25519 [privateSeed].
///
/// The signature is taken over `PolicyLoader.canonicalPayload` — the document
/// with `signature` removed and keys sorted — so reformatting the file in an
/// editor does not invalidate it. Without that, an administrator who pretty-
/// printed their policy would see a failure indistinguishable from tampering.
List<int> signPolicyDocument({
  required Map<String, Object?> document,
  required List<int> privateSeed,
}) {
  final pair = PolicyEd25519KeyPair.fromSeed(privateSeed);
  return pair.sign(utf8.encode(PolicyLoader.canonicalPayload(document)));
}

/// The public verify key for [privateSeed].
///
/// Emitted by `sign`, because an administrator needs it at install time and
/// deriving it by hand is an error nobody should have to make. There is no
/// other way to obtain it without putting a signer in a product.
List<int> policyPublicKeyFor(List<int> privateSeed) =>
    PolicyEd25519KeyPair.fromSeed(privateSeed).publicKey;
