// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The authentication token this process publishes in its peer manifest
/// and requires of every peer that dials its server.
///
/// ### What it defends against, and what it does not
///
/// CXP servers bind loopback, and every Crux product binds a **fixed
/// default port** (54322–54325). Loopback is reachable by every process on
/// the machine - including ones the spec's trust model (§11) never meant
/// to include: another user on a shared workstation, a sandboxed app with
/// a network-client entitlement and no file access, a container with host
/// networking. The spec assumes "every process running as the user is
/// equally trusted, which is the same assumption the user's shell makes";
/// the fixed port made the real boundary wider than that.
///
/// The token restores the spec's boundary. A peer learns it from the
/// target's manifest, which lives in the user's private application-data
/// directory (`sharedCxpManifestDirectory`) - so being able to present it
/// proves exactly what the spec already assumes: the dialler can read the
/// user's files. Every legitimate peer reads that file anyway to learn the
/// port, so the cost of carrying one more field is nothing.
///
/// It does **not** authenticate a process running as the user: such a
/// process reads the manifest and presents the token like any peer. That
/// is the trust model, not a gap in the mechanism, and it is why the token
/// is not called a password.
///
/// ### Why one token per process, minted here
///
/// `LocalCxpServer` requires it and `CxpManifestWriter` publishes it, and
/// the two objects are constructed separately in every product. A token
/// they both default to is what lets the enforcement land in the shared
/// layer without four products each threading a value from one to the
/// other - and without a product that forgets the threading silently
/// refusing every peer. Both accept an explicit token for tests and for
/// hosts that run several peers in one process with distinct secrets.
///
/// Minted lazily on first use from the platform's secure random source.
final String cxpProcessAuthToken = generateCxpAuthToken();

/// A fresh 128-bit token from `Random.secure()`, as 32 lowercase hex
/// digits - filename-safe and JSON-safe, since it travels in both.
String generateCxpAuthToken() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Whether [presented] is [expected], compared in time that does not
/// depend on where the two first differ.
///
/// A missing token (`null`) never matches. Lengths are compared as part of
/// the same accumulated difference rather than as an early return; the
/// comparison still runs over the shorter of the two.
///
/// Proofs ([cxpAuthProof]) are compared with this function too: a proof is
/// a hex string of fixed length, and the same timing rule applies.
bool cxpAuthTokensMatch(String? presented, String expected) {
  if (presented == null) return false;
  final a = presented.codeUnits;
  final b = expected.codeUnits;
  var difference = a.length ^ b.length;
  final overlap = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < overlap; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// A fresh nonce for one `hello` (wire 1.3, §7.4): the same 128 bits from
/// the same source as a token, in the same 32-hex-digit shape.
String generateCxpAuthNonce() => generateCxpAuthToken();

/// The label under which a dialler proves it holds the listener's token.
/// See [cxpAuthProof].
const String cxpHelloProofLabel = 'cxp-hello';

/// The label under which a listener proves it holds its own token. See
/// [cxpAuthProof].
const String cxpHelloAckProofLabel = 'cxp-hello-ack';

/// Mutual authentication (wire 1.3, §7.4): proof that a peer holds [token]
/// without the token itself crossing the wire.
///
/// ### Why the token stopped travelling
///
/// Under 1.2 the dialler sent the listener's token verbatim in its `hello`.
/// That authenticated the dialler, but it handed the token to whatever had
/// answered the port - and a process that binds a peer's well-known port
/// after the peer exits, while its manifest still names it, is dialled in
/// the peer's place. Nothing the listener could then put in its `hello_ack`
/// would prove anything: it had just been given the secret, and could echo
/// it, or anything derived from it, as well as the real peer could.
///
/// So neither side sends the token. The dialler sends a fresh [nonce] and
/// `HMAC-SHA256(key = token, message = "cxp-hello:" + nonce)`; the listener
/// recomputes it from the token it holds, and answers with
/// `HMAC-SHA256(key = token, message = "cxp-hello-ack:" + nonce)`, which
/// the dialler checks against the token it read from the manifest. A
/// process that does not hold the token can compute neither, and learns
/// nothing from either that lets it compute the other: the two labels keep
/// one side's proof from being replayed as the other's, and the nonce keeps
/// a proof captured on one connection from being replayed on another.
///
/// The key is the token's UTF-8 bytes, the message is the UTF-8 bytes of
/// `'$label:$nonce'`, and the proof is the digest as 64 lowercase hex
/// digits. Stated this plainly so that a second implementation can be
/// written from the spec alone and agree byte for byte.
String cxpAuthProof({
  required String token,
  required String nonce,
  required String label,
}) {
  final mac = Hmac(sha256, utf8.encode(token));
  return mac.convert(utf8.encode('$label:$nonce')).toString();
}

/// Whether a peer that announces [cxpVersion] takes part in mutual
/// authentication (wire 1.3, §7.4): the major component is `1` and the
/// minor is at least `3`, or the major is greater than `1`.
///
/// A dialler decides *from the manifest* how to present the listener's
/// token, never from what the port answers: a manifest the other user's
/// process cannot write, a port it can bind. `null` - a manifest written
/// before 1.3 carries no `cxp_version` - reads as "no", and the dialler
/// then presents the token verbatim, as 1.2 did; the manifest's author has
/// not promised to answer a proof. An unparseable value reads as "no" too.
bool cxpVersionHasMutualAuth(String? cxpVersion) {
  if (cxpVersion == null) return false;
  final parts = cxpVersion.split('.');
  final major = int.tryParse(parts.first);
  if (major == null) return false;
  if (major > 1) return true;
  if (major < 1) return false;
  final minor = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  return minor != null && minor >= 3;
}
