// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

/// The authentication token this process publishes in its peer manifest
/// and requires of every peer that dials its server.
///
/// ### What it defends against, and what it does not
///
/// CXP servers bind loopback, and every Crux product binds a **fixed
/// default port** (54322–54325). Loopback is reachable by every process on
/// the machine — including ones the spec's trust model (§11) never meant
/// to include: another user on a shared workstation, a sandboxed app with
/// a network-client entitlement and no file access, a container with host
/// networking. The spec assumes "every process running as the user is
/// equally trusted, which is the same assumption the user's shell makes";
/// the fixed port made the real boundary wider than that.
///
/// The token restores the spec's boundary. A peer learns it from the
/// target's manifest, which lives in the user's private application-data
/// directory (`sharedCxpManifestDirectory`) — so being able to present it
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
/// other — and without a product that forgets the threading silently
/// refusing every peer. Both accept an explicit token for tests and for
/// hosts that run several peers in one process with distinct secrets.
///
/// Minted lazily on first use from the platform's secure random source.
final String cxpProcessAuthToken = generateCxpAuthToken();

/// A fresh 128-bit token from `Random.secure()`, as 32 lowercase hex
/// digits — filename-safe and JSON-safe, since it travels in both.
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
