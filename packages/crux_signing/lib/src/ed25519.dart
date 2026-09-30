// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Ed25519 signature **verification**, and nothing else.
///
/// ### Why this is hand-written rather than a package dependency
///
/// The obvious move is `package:cryptography`. It cannot be used here, and the
/// reason is legal rather than technical: the suite's export-control position
/// rests on one load-bearing fact — *encryption implementations live in the
/// closed Pro overlays; open core calls TLS and hashes, it does not encrypt* —
/// and each product enforces it with a static guard over
/// the resolved `pubspec.lock`. `cryptography` ships AES-GCM and ChaCha20, so
/// pulling it into a `crux-shared` package would put a cipher in every product
/// and in the open-core tree, which at the open-core flip turns into an EAR
/// §742.15(b) notification obligation and makes the store builds'
/// `ITSAppUsesNonExemptEncryption=false` declaration untrue. A licence
/// validator is not worth either.
///
/// ### Three consumers, one implementation
///
/// This began as `crux_license`'s private verifier and now lives in
/// `crux_signing` because two more callers need the same primitive and a
/// second implementation is the failure this package exists to prevent:
///
/// - **`crux_license`** — licence keys and licence files.
/// - **`crux_policy`** — the organization's signed `.crux-policy.json`. That
///   file arrives from a network share an attacker may be able to write to,
///   which is the entire reason it carries a signature.
/// - **plugin governance** — a decoder or widget allowlisted by signing key.
///
/// The move changed no algorithm and no test vector. Grep proves there is
/// exactly one Ed25519 implementation in the suite.
///
/// What is here instead is a **digital-signature verifier with no cipher in
/// it** — no symmetric algorithm, no key agreement, no key generation, and no
/// signing. Verification needs a public key and nothing else.
///
/// ### Correctness
///
/// Implemented from RFC 8032 §5.1.7 and checked against the RFC's own test
/// vectors in `test/ed25519_test.dart`, including the malleability and
/// small-order cases that a naive implementation accepts. Rejecting bad input
/// is the entire job, so the negative vectors matter more than the positive
/// ones.
///
/// Not constant-time, and it does not need to be: every input is public. There
/// is no secret here to leak through a timing channel — the signature, the
/// message and the public key all travel in the clear by design.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha512;

/// 2^255 - 19, the field prime.
final BigInt _p = (BigInt.one << 255) - BigInt.from(19);

/// The group order: 2^252 + 27742317777372353535851937790883648493.
final BigInt _l =
    (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');

/// The curve constant d = -121665/121666 (mod p).
final BigInt _d = (BigInt.from(-121665) * _inverse(BigInt.from(121666))) % _p;

/// sqrt(-1) mod p, needed to pick between the two roots on decompression.
final BigInt _sqrtMinusOne = BigInt.two.modPow((_p - BigInt.one) >> 2, _p);

/// The base point B, in extended coordinates.
final _Point _base = _basePoint();

/// Verify [signature] over [message] against the 32-byte Ed25519 public key
/// [publicKey].
///
/// Total: returns `false` for every malformed input — wrong lengths, a public
/// key that is not a curve point, a non-canonical scalar — rather than
/// throwing. A licence validator is handed arbitrary user text, and "this is
/// not a valid signature" is the same answer whatever the reason.
bool ed25519Verify({
  required List<int> message,
  required List<int> signature,
  required List<int> publicKey,
}) {
  if (signature.length != 64 || publicKey.length != 32) return false;

  final r = signature.sublist(0, 32);
  final s = _littleEndian(signature.sublist(32));

  // RFC 8032 §5.1.7 step 1: S must be canonical. Without this check every
  // signature has an unbounded family of equivalents, which turns "the same
  // licence key" into a set rather than a value.
  if (s >= _l) return false;

  final a = _decodePoint(publicKey);
  if (a == null) return false;
  final rPoint = _decodePoint(r);
  if (rPoint == null) return false;

  final k =
      _littleEndian(
        sha512.convert(<int>[...r, ...publicKey, ...message]).bytes,
      ) %
      _l;

  // [S]B == R + [k]A
  final left = _scalarMult(_base, s);
  final right = _add(rPoint, _scalarMult(a, k));
  return _encodePoint(left) == _encodePoint(right);
}

/// A point in extended twisted-Edwards coordinates (X : Y : Z : T),
/// where x = X/Z, y = Y/Z and x·y = T/Z.
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

_Point _basePoint() {
  final y = BigInt.from(4) * _inverse(BigInt.from(5)) % _p;
  final x = _recoverX(y, 0)!;
  return _Point(x, y, BigInt.one, x * y % _p);
}

BigInt _inverse(BigInt value) => value.modPow(_p - BigInt.two, _p);

BigInt _littleEndian(List<int> bytes) {
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

/// Recover x from y and the sign bit, or `null` when no such point exists.
BigInt? _recoverX(BigInt y, int sign) {
  if (y >= _p) return null;
  final y2 = y * y % _p;
  final u = (y2 - BigInt.one) % _p;
  final v = (_d * y2 + BigInt.one) % _p;
  // x = u/v computed as u·v^3·(u·v^7)^((p-5)/8), the standard shortcut for
  // p ≡ 5 (mod 8).
  final v3 = v * v % _p * v % _p;
  final v7 = v3 * v3 % _p * v % _p;
  var x = u * v3 % _p * (u * v7).modPow((_p - BigInt.from(5)) >> 3, _p) % _p;

  final check = v * x % _p * x % _p;
  if (check != u % _p) {
    if (check == (-u) % _p) {
      x = x * _sqrtMinusOne % _p;
    } else {
      return null;
    }
  }
  if (x == BigInt.zero && sign == 1) return null;
  if (x.isOdd != (sign == 1)) x = _p - x;
  return x;
}

_Point? _decodePoint(List<int> encoded) {
  if (encoded.length != 32) return null;
  final bytes = Uint8List.fromList(encoded);
  final sign = bytes[31] >> 7;
  bytes[31] &= 0x7f;
  final y = _littleEndian(bytes);
  final x = _recoverX(y, sign);
  if (x == null) return null;
  return _Point(x, y, BigInt.one, x * y % _p);
}

String _encodePoint(_Point point) {
  final zInverse = _inverse(point.z);
  final x = point.x * zInverse % _p;
  final y = point.y * zInverse % _p;
  final bytes = Uint8List(32);
  var value = y;
  for (var i = 0; i < 32; i++) {
    bytes[i] = (value & BigInt.from(0xff)).toInt();
    value >>= 8;
  }
  if (x.isOdd) bytes[31] |= 0x80;
  // Compared as a string rather than byte-by-byte so the caller cannot get
  // list identity wrong; the value is public, so there is nothing to leak.
  return String.fromCharCodes(bytes);
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
