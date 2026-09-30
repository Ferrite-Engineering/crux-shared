// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite live statistics strip for the EDACrux suite.
///
/// The collapsible ambient performance monitor that docks above the status
/// bar, plus the app-level collectors every product shares:
///
/// * `cruxFrameStatsProvider` — FPS and frame-budget overruns, from
///   `SchedulerBinding`'s real frame timings.
/// * `cruxMemoryStatsProvider` — process RSS on a 2 s poll.
/// * `CruxStatsStrip` — renders whatever `CruxStatSegment`s the host
///   supplies, so product-specific readings (SimCrux's queue depth,
///   NetCrux's layout time) are the same type as the shared ones.
/// * `CruxSparkline` — the miniature history chart, ported from WaveCrux.
///
/// The strip has no product knowledge and does not gate its own platform
/// visibility; the host decides whether to render it and what goes in it.
library;

export 'src/format/crux_byte_format.dart';
export 'src/models/crux_frame_stats.dart';
export 'src/models/crux_memory_stats.dart';
export 'src/models/crux_stat_segment.dart';
export 'src/providers/crux_frame_stats_provider.dart';
export 'src/providers/crux_memory_stats_provider.dart';
export 'src/widgets/crux_paint_timing_probe.dart';
export 'src/widgets/crux_sparkline.dart';
export 'src/widgets/crux_stats_strip.dart';
