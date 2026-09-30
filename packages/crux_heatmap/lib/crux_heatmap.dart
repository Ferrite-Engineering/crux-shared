// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Calendar heatmap grid shared by the EDACrux products that keep a trend
/// store.
///
/// Extracted 2026-08-18 from LintCrux's and SimCrux's independently-written
/// copies, which had byte-identical public surfaces and differed only in how
/// a day's value maps to a colour. That mapping stays in the products; this
/// package owns layout and interaction.
library;

export 'src/crux_calendar_heatmap.dart';
