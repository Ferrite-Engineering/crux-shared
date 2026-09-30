// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Asking the C library whether a pid names a process, dispatched by
/// platform.
///
/// Discovery asks it of a peer's pid on every scan, on the isolate that
/// started discovery — the UI isolate, in the products. The implementation
/// calls `kill(pid, 0)` through `dart:ffi`: a system call, where running the
/// `kill` command cost a process launch per pid per scan. A browser build
/// has no `dart:ffi` and no processes, and gets a stub that cannot ask.
library;

export 'cxp_kill_zero_stub.dart' if (dart.library.ffi) 'cxp_kill_zero_ffi.dart';
