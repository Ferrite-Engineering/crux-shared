// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// One labelled reading in the live statistics strip.
///
/// The strip renders whatever segments the host supplies; it has no opinion
/// about what a product measures. SimCrux's job-scheduler segments and
/// NetCrux's layout-time segment are both just entries in this list.
@immutable
class CruxStatSegment {
  /// Creates a segment.
  const CruxStatSegment({
    required this.label,
    required this.value,
    this.sparkline = const <double>[],
    this.tooltip,
    this.emphasis = CruxStatEmphasis.normal,
    this.leading,
  });

  /// Short caption, e.g. `FPS` or `Queue`.
  final String label;

  /// Formatted reading, e.g. `59.8` or `142 MB`. Hosts format their own
  /// units — the strip does not guess whether 1024 means bytes or tests.
  final String value;

  /// Optional history, oldest first. Empty hides the sparkline.
  final List<double> sparkline;

  /// Optional hover text expanding on what the reading means.
  final String? tooltip;

  /// How prominently to render the value.
  final CruxStatEmphasis emphasis;

  /// Optional leading widget (a spinner for a running job, say).
  final Widget? leading;
}

/// Visual weight for a segment's value.
enum CruxStatEmphasis {
  /// Ordinary reading.
  normal,

  /// Dimmed — the measurement is stale or the subsystem is idle.
  ///
  /// Distinct from omitting the segment: a segment that disappears when
  /// idle makes the strip's layout jump every time a run starts and stops,
  /// which is worse than a greyed number that stays put.
  dimmed,

  /// Highlighted — something is out of budget and worth a glance.
  warning,
}
