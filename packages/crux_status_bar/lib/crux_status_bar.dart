// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite bottom **status bar** for the EDACrux suite.
///
/// A single left-aligned, fixed-height, theme-aware bar mounted at the window
/// bottom by every product (WaveCrux, NetCrux, LintCrux, SimCrux) so the
/// suite's bottom-of-window chrome is consistent. WaveCrux is the canonical
/// reference for the look (24 dp tall on desktop, monospace 11 pt,
/// `surfaceContainerHighest` background with a 0.5 dp `dividerColor` top
/// border).
///
/// The package hard-codes **no** per-app content. The host contributes widgets
/// into ordered slots — `leading`, `segments`, `segmentsTrailing`, `center`
/// and `trailing` — generalizing WaveCrux's `statusBarTrailingWidgetsProvider`
/// open-core/Pro extension seam into a reusable API. Use `CruxStatusSegment`
/// for plain-text metric segments.
library;

export 'src/crux_status_bar.dart';
