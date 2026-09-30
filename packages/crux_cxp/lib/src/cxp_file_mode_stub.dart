// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A host without `dart:ffi` — a browser, which has no files to protect.
library;

/// Sets [path]'s permission bits to [mode]. Here: nothing to set, so
/// nothing is set.
bool setPosixFileMode(String path, int mode) => false;
