// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/src/cxp_kill_zero.dart';

/// The outcome of asking whether a peer manifest's owning process is still
/// running on this machine.
///
/// CXP peers are all localhost, single-user processes, so a manifest's pid
/// always names a process on *this* host — which makes a direct liveness
/// probe possible and definitive where the platform supports one. When it
/// does not, the answer is [indeterminate] and callers fall back to the
/// time-to-live heuristic; a live-but-quiet peer must never be pruned on a
/// guess.
enum PidLiveness {
  /// The process is running.
  alive,

  /// The process is definitively gone (e.g. `kill(pid, 0)` failed with
  /// `ESRCH`, or `/proc/<pid>` is absent on Linux). Safe to reap the
  /// manifest at once — this is not a merely-asleep peer.
  dead,

  /// Liveness could not be determined on this platform (Windows, a C
  /// library without `kill`, a permission error, or an unparseable pid).
  /// Callers must treat the manifest as present and let the TTL decide.
  indeterminate,
}

/// Extracts the pid embedded in a CXP `peer_id`.
///
/// The conventional form is `<product>-<pid>-<startedAtMillis>` (see
/// `PeerIdentity.peerId`). The pid is the **second-to-last** hyphen segment,
/// which is robust to a product short-name that itself contains hyphens.
/// Returns null when the id has fewer than three segments or the pid segment
/// is not a positive integer — both of which mean "cannot determine",
/// yielding [PidLiveness.indeterminate] downstream.
int? pidFromPeerId(String peerId) {
  final segments = peerId.split('-');
  if (segments.length < 3) return null;
  final pidText = segments[segments.length - 2];
  final pid = int.tryParse(pidText);
  if (pid == null || pid <= 0) return null;
  return pid;
}

/// Whether the process named by [pid] is alive on this machine.
///
/// [operatingSystem] defaults to [Platform.operatingSystem] and is injectable
/// for tests. The probe is deliberately **non-signalling** — it never delivers
/// a real signal to the target:
///
/// - **Linux**: presence of `/proc/<pid>` (no subprocess, no signal).
/// - **macOS / other POSIX**: the C library's `kill(pid, 0)`, which sends no
///   signal but succeeds iff the process exists and is signallable by us.
///   Success is [PidLiveness.alive]; `ESRCH` ("no such process") is
///   [PidLiveness.dead]; any other failure (notably `EPERM`, a process owned
///   by another user) is [PidLiveness.indeterminate] so we never reap on an
///   ambiguous result. So is a pid a `pid_t` cannot hold.
/// - **Windows / anything else**: [PidLiveness.indeterminate]; there is no
///   dependency-free probe, so the TTL is the sole authority there.
///
/// No probe starts a process. Discovery asks this of every peer on every
/// scan, on the isolate that runs it — the UI isolate, in the products — and
/// the `kill -0` command this replaced was a process launch each time, which
/// `dart:io` performs on the calling isolate even through `Process.run`: a
/// few milliseconds of frozen UI per peer, every scan interval, in every
/// product for as long as it runs.
PidLiveness pidLiveness(int pid, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  switch (os) {
    case 'linux':
      // /proc is authoritative on Linux and needs no subprocess.
      try {
        return Directory('/proc/$pid').existsSync()
            ? PidLiveness.alive
            : PidLiveness.dead;
      } on FileSystemException {
        return PidLiveness.indeterminate;
      }
    case 'macos':
    case 'android':
    case 'fuchsia':
      return _killZeroLiveness(pid);
    case 'windows':
      return PidLiveness.indeterminate;
    default:
      // Unknown POSIX-ish platform: try kill(pid, 0), fall back to
      // indeterminate.
      return _killZeroLiveness(pid);
  }
}

/// `ESRCH`, "no such process" — the same value on every POSIX system.
const int _esrch = 3;

PidLiveness _killZeroLiveness(int pid) {
  final error = posixKillZero(pid);
  if (error == 0) return PidLiveness.alive;
  // ESRCH is the one definitive failure. Anything else (EPERM, or no answer
  // at all) is ambiguous and must not reap.
  if (error == _esrch) return PidLiveness.dead;
  return PidLiveness.indeterminate;
}

/// Convenience: the liveness of the process that owns [peerId], or
/// [PidLiveness.indeterminate] when the pid cannot be parsed.
PidLiveness peerIdLiveness(String peerId, {String? operatingSystem}) {
  final pid = pidFromPeerId(peerId);
  if (pid == null) return PidLiveness.indeterminate;
  return pidLiveness(pid, operatingSystem: operatingSystem);
}
