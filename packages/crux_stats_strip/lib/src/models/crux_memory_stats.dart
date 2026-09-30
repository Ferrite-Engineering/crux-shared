// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Process-level memory snapshot for the live statistics strip.
///
/// Deliberately process RSS rather than Dart heap: the strip's question is
/// "is this app about to become a problem on my machine", and on every
/// product in the suite the answer is dominated by things outside the Dart
/// heap — a memory-mapped waveform, a Yosys subprocess's output buffer, an
/// elkjs bundle inside a JS runtime. Reporting only the Dart heap would
/// show a flat, reassuring line while the process grew to several GB.
@immutable
class CruxMemoryStats {
  /// Creates a snapshot.
  const CruxMemoryStats({
    required this.residentBytes,
    required this.recentResidentBytes,
  });

  /// The empty state, before the first sample.
  static const CruxMemoryStats empty = CruxMemoryStats(
    residentBytes: 0,
    recentResidentBytes: <double>[],
  );

  /// Current resident set size in bytes, or 0 when unavailable.
  final int residentBytes;

  /// Recent RSS samples in bytes, oldest first — the sparkline series.
  final List<double> recentResidentBytes;

  /// Whether a real measurement has been taken.
  bool get hasSample => residentBytes > 0;

  @override
  String toString() => 'CruxMemoryStats(rss: $residentBytes)';
}
