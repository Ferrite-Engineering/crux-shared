// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One source file handed to a scanner: the path a finding names (normally
/// relative to the repository root, `/`-separated) and the file's text.
///
/// Scanners take text rather than reading the disk, so a guard's own tests
/// can feed it fixtures, and so the host test decides what is in scope.
@immutable
final class CruxGuardSource {
  /// Creates a source.
  const CruxGuardSource({required this.path, required this.source});

  /// The path a finding names.
  final String path;

  /// The file's text.
  final String source;
}

/// One thing a guard found wrong.
@immutable
final class CruxGuardFinding {
  /// Creates a finding.
  const CruxGuardFinding({
    required this.path,
    required this.line,
    required this.detail,
  });

  /// The file, or a description of the list entry, the finding is about.
  final String path;

  /// The 1-based line, or 0 when the finding is not about a line.
  final int line;

  /// What is wrong and what to do about it.
  final String detail;

  @override
  String toString() => line > 0 ? '$path:$line: $detail' : '$path: $detail';
}

/// What a scanner reports: its findings, and how much it looked at, so a host
/// test can assert the scan was not vacuous.
@immutable
final class CruxGuardResult {
  /// Creates a result.
  const CruxGuardResult({
    required this.findings,
    required this.filesScanned,
    required this.matchesSeen,
  });

  /// Everything the guard found wrong. Empty is green.
  final List<CruxGuardFinding> findings;

  /// How many sources were scanned.
  final int filesScanned;

  /// How many sites the guard's pattern matched, exempted or not.
  final int matchesSeen;

  /// Whether there is nothing to fix.
  bool get isClean => findings.isEmpty;

  /// The findings, one per line, for an `expect` reason.
  String describe() => findings.join('\n');
}

/// The 1-based line holding [offset] in [source].
int lineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}
