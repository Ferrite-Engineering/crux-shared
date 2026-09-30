// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

/// The C library's `kill(2)`. `pid_t` is a signed 32-bit integer on every
/// platform this runs on.
@Native<Int32 Function(Int32, Int32)>(symbol: 'kill', isLeaf: true)
external int _kill(int pid, int signal);

/// The calling thread's `errno`, in Darwin's C library.
@Native<Pointer<Int32> Function()>(symbol: '__error', isLeaf: true)
external Pointer<Int32> _darwinErrno();

/// The calling thread's `errno`, in Android's C library.
@Native<Pointer<Int32> Function()>(symbol: '__errno', isLeaf: true)
external Pointer<Int32> _bionicErrno();

/// The calling thread's `errno`, in glibc and musl.
@Native<Pointer<Int32> Function()>(symbol: '__errno_location', isLeaf: true)
external Pointer<Int32> _errnoLocation();

/// The largest pid a `pid_t` can hold.
const int _maxPid = 0x7fffffff;

enum _Libc { darwin, bionic, other }

final _Libc _libc = Platform.isMacOS || Platform.isIOS
    ? _Libc.darwin
    : Platform.isAndroid
    ? _Libc.bionic
    : _Libc.other;

/// `kill(pid, 0)`: whether [pid] names a process this process may signal.
/// No signal is sent.
///
/// Returns 0 when the call succeeded and the `errno` it failed with
/// otherwise — `ESRCH` when no process has the pid, `EPERM` when one does
/// and another user owns it. Returns null when the question cannot be
/// asked: on Windows, for a pid a `pid_t` cannot hold (which the `kill`
/// command refuses as an illegal process id), and wherever the process
/// exports no `kill`. Never throws.
///
/// Dart does not promise that `errno` survives from one native call to the
/// next. The two calls here are adjacent leaf calls, so nothing that could
/// fail and set it should run between them — and if something did, the
/// value read would almost certainly not be `ESRCH`, which a caller reads
/// as "cannot tell", not "dead". The answer that deletes a manifest cannot
/// come from a clobbered `errno`.
int? posixKillZero(int pid) {
  if (Platform.isWindows || pid <= 0 || pid > _maxPid) return null;
  // Resolved first, so the branch below is the only thing between `kill`
  // returning and `errno` being read.
  final libc = _libc;
  try {
    if (_kill(pid, 0) == 0) return 0;
    return switch (libc) {
      _Libc.darwin => _darwinErrno().value,
      _Libc.bionic => _bionicErrno().value,
      _Libc.other => _errnoLocation().value,
    };
    // A `@Native` symbol is bound on first call, and a process that does not
    // export it raises ArgumentError there. That is a platform that cannot
    // be asked, which is an answer — null — not a crash.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return null;
  }
}
