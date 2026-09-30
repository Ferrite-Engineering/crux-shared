// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Controls how the application responds when the active source file changes
/// on disk.
///
/// Generic across the suite: every Crux product can watch its primary input
/// (WaveCrux's VCD/FST; future products' own inputs) and react to
/// external changes.
enum AutoReloadMode {
  /// Show a banner and ask the user whether to reload.
  prompt,

  /// Reload automatically without prompting.
  auto,

  /// Ignore file-change events entirely.
  off,
}
