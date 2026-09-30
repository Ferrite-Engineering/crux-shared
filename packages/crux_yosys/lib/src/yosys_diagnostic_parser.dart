// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_yosys/src/yosys_diagnostic.dart';

/// Parses Yosys's stderr output into structured [YosysDiagnostic]s.
///
/// Yosys does not have a stable, machine-readable diagnostic format. Real
/// captures contain a mix of:
///
/// * `path/foo.v:3: ERROR: syntax error, unexpected '...'`
/// * `path/foo.v:3.5: ERROR: ...` (line.column)
/// * `path/foo.v:3:5: ERROR: ...` (colon-separated column)
/// * `ERROR: ...` (no source location)
/// * `Warning: ...`
/// * Untagged informational lines (banners, log messages)
///
/// The parser handles all of these conservatively: every captured line is
/// either matched against the location-prefixed pattern or against a
/// severity-prefixed pattern. Unmatched lines are dropped (they're log
/// noise the diagnostics panel doesn't need to render); callers can still
/// surface the raw stderr separately when they want full transparency.
class YosysDiagnosticParser {
  /// Creates a parser. Stateless.
  const YosysDiagnosticParser();

  /// Splits [stderr] into lines and returns the structured diagnostics
  /// found. The order matches Yosys's output order.
  List<YosysDiagnostic> parse(String stderr) {
    final out = <YosysDiagnostic>[];
    for (final raw in const LineSplitter().convert(stderr)) {
      final diagnostic = _parseLine(raw);
      if (diagnostic != null) {
        out.add(diagnostic);
      }
    }
    return out;
  }

  YosysDiagnostic? _parseLine(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final locMatch = _locationPattern.firstMatch(trimmed);
    if (locMatch != null) {
      final file = locMatch.group(1)!;
      final line = int.tryParse(locMatch.group(2)!);
      final column = locMatch.group(3) != null
          ? int.tryParse(locMatch.group(3)!)
          : null;
      final rest = locMatch.group(4)!;
      final (severity, message) = _splitSeverity(rest);
      return YosysDiagnostic(
        severity: severity,
        message: message,
        filePath: file,
        line: line,
        column: column,
        rawLine: raw,
      );
    }

    final severityMatch = _bareSeverityPattern.firstMatch(trimmed);
    if (severityMatch != null) {
      final severity = _severityFromLabel(severityMatch.group(1)!);
      final message = severityMatch.group(2)!.trim();
      return YosysDiagnostic(
        severity: severity,
        message: message,
        rawLine: raw,
      );
    }
    return null;
  }

  /// Yosys location prefix:
  /// `path:line[(.|:)col][-endline(.|:)endcol]: rest`.
  ///
  /// Accepts either `.` or `:` between line and column to handle both
  /// shapes Yosys has emitted across versions.
  static final RegExp _locationPattern = RegExp(
    r'^([^:\s][^:]*?):(\d+)(?:[.:](\d+))?(?:-\d+[.:]\d+)?:\s*(.*)$',
  );

  /// Bare severity prefix: `ERROR: msg`, `Warning: msg`, `Info: msg`.
  static final RegExp _bareSeverityPattern = RegExp(
    r'^(ERROR|Error|Warning|WARN|Info|INFO|NOTE|Note):\s*(.*)$',
  );

  static (YosysDiagnosticSeverity, String) _splitSeverity(String text) {
    final m = _bareSeverityPattern.firstMatch(text);
    if (m != null) {
      return (_severityFromLabel(m.group(1)!), m.group(2)!.trim());
    }
    // No explicit severity label after the location prefix → default to
    // error. Yosys's untagged "path:line: ..." messages are almost always
    // errors that crashed the run.
    return (YosysDiagnosticSeverity.error, text.trim());
  }

  static YosysDiagnosticSeverity _severityFromLabel(String label) {
    switch (label.toLowerCase()) {
      case 'error':
        return YosysDiagnosticSeverity.error;
      case 'warning':
      case 'warn':
        return YosysDiagnosticSeverity.warning;
      case 'info':
      case 'note':
        return YosysDiagnosticSeverity.info;
      default:
        return YosysDiagnosticSeverity.error;
    }
  }
}
