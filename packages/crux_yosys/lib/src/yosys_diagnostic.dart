// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Severity of a single Yosys diagnostic line.
enum YosysDiagnosticSeverity {
  /// Hard error — Yosys could not continue.
  error,

  /// Warning — Yosys continued but flagged something suspicious.
  warning,

  /// Informational note (rare in real Yosys output but accepted by the
  /// parser so we don't drop them silently).
  info,
}

/// One parsed line from Yosys's stderr stream.
///
/// `file:line:col` style messages (the common Verilator-like shape) yield
/// a diagnostic with [filePath], [line], and optionally [column]
/// populated. Free-form `ERROR: ...` lines without a file prefix yield a
/// diagnostic with only [severity] and [message] set.
@immutable
class YosysDiagnostic {
  /// Creates a diagnostic.
  const YosysDiagnostic({
    required this.severity,
    required this.message,
    this.filePath,
    this.line,
    this.column,
    this.rawLine,
  });

  /// The severity level.
  final YosysDiagnosticSeverity severity;

  /// Free-form message text after the severity prefix and source range.
  final String message;

  /// Absolute or relative path of the source file Yosys cited, if any.
  final String? filePath;

  /// 1-based line number Yosys cited, if any.
  final int? line;

  /// 1-based column number Yosys cited, if any.
  final int? column;

  /// The original line from the stderr stream that produced this
  /// diagnostic, preserved for diagnostics-panel display.
  final String? rawLine;

  /// Returns a copy with the given fields replaced.
  YosysDiagnostic copyWith({
    YosysDiagnosticSeverity? severity,
    String? message,
    String? filePath,
    int? line,
    int? column,
    String? rawLine,
  }) {
    return YosysDiagnostic(
      severity: severity ?? this.severity,
      message: message ?? this.message,
      filePath: filePath ?? this.filePath,
      line: line ?? this.line,
      column: column ?? this.column,
      rawLine: rawLine ?? this.rawLine,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! YosysDiagnostic) return false;
    return other.severity == severity &&
        other.message == message &&
        other.filePath == filePath &&
        other.line == line &&
        other.column == column &&
        other.rawLine == rawLine;
  }

  @override
  int get hashCode =>
      Object.hash(severity, message, filePath, line, column, rawLine);

  @override
  String toString() {
    final pos = filePath == null
        ? ''
        : line == null
        ? '$filePath: '
        : column == null
        ? '$filePath:$line: '
        : '$filePath:$line:$column: ';
    return '$pos${severity.name.toUpperCase()}: $message';
  }
}
