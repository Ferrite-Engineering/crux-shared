// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Why a run was not read by a reader verified for it.
///
/// A run with one of these is still read, best-effort, and its
/// `FlowRunRef.verified` is false: what it shows has not been checked
/// against the tool version that wrote it.
enum FlowReaderUnsupported {
  /// The run states no tool version, or one no reader was verified against
  /// (a release newer or older than the verified range).
  versionUnknown('version_unknown'),

  /// The directory is not laid out as a run of the kind it was read as.
  layoutUnknown('layout_unknown'),

  /// A record in the run is not the shape its schema says.
  schemaUnknown('schema_unknown');

  const FlowReaderUnsupported(this.wireName);

  /// The stable token (telemetry and metrics value).
  final String wireName;
}
