// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite tabbed dock for the EDACrux suite.
///
/// A VSCode-style region container mounted inside a `CruxIdeLayout` region:
/// tab strip with badges and per-tab close, auto-hiding single-tab header,
/// collapse / maximize / pop-out affordances, auto-reveal of newly activated
/// on-demand tabs. Hosts assemble `CruxDockEntry` lists from their own
/// providers — the package hard-codes no per-app content.
library;

export 'src/crux_dock.dart';
export 'src/crux_dock_restore_bar.dart';
export 'src/dock_entry.dart';
