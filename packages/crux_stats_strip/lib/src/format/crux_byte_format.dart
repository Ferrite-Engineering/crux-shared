// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Formats [bytes] for the strip's narrow value column.
///
/// Whole units below a gigabyte, one decimal above: at 787 MB the tenths
/// place is a digit that changes constantly and tells the reader nothing,
/// while at 3.2 GB it is the difference between comfortable and worrying.
///
/// Lived as a verbatim copy in NetCrux's and SimCrux's strip files until
/// WaveCrux joined them with a third formatter of its own — and a Memory
/// segment reading "771.4 MB" beside NetCrux's "787 MB" made two products
/// look like they were measuring different things.
///
/// Binary units throughout (1 KB = 1024 B), matching every other memory
/// figure the suite reports.
String cruxFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
