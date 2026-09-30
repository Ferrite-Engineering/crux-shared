// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A host without `dart:ffi` — a browser, which has no processes to probe.
library;

/// `kill(pid, 0)`. Here: nothing can be asked, so the answer is null.
int? posixKillZero(int pid) => null;
