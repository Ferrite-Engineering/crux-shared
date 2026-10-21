// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';
import 'package:meta/meta.dart';

/// A source range recovered from a Yosys `src` attribute.
///
/// Yosys writes `file:startLine.startCol-endLine.endCol`; older releases and
/// some frontends write the shorter `file:line` or `file:line.col`. A cell
/// built from several statements carries several spans joined by `|`, the
/// first being the declaration site. Place-and-route tools copy the
/// attribute through unchanged, so the same grammar arrives in nextpnr's
/// `sources` lists and in a synthesized design's cell attributes.
///
/// The file is kept exactly as recorded. It may be an absolute path on the
/// machine that ran synthesis, in either path style; [matchSourceBySuffix]
/// relates it to a design's own files, and nothing here opens it.
@immutable
class SrcSpan {
  /// Creates a span.
  const SrcSpan({
    required this.file,
    required this.startLine,
    this.startCol,
    this.endLine,
    this.endCol,
  });

  /// Reads a span written by [toJson].
  factory SrcSpan.fromJson(Map<String, Object?> json) => SrcSpan(
    file: requireString(json['file'], 'file'),
    startLine: requireInt(json['start_line'], 'start_line'),
    startCol: optionalInt(json['start_col'], 'start_col'),
    endLine: optionalInt(json['end_line'], 'end_line'),
    endCol: optionalInt(json['end_col'], 'end_col'),
  );

  /// Parses one span, or returns null when [raw] is not one.
  ///
  /// The file is everything before the **last** colon, so a Windows path
  /// (`C:\rtl\top.v:12.3-14.5`) keeps its drive letter. A line below 1, a
  /// non-numeric position, or an end before the start is refused rather
  /// than guessed at: a wrong line sends a reader to unrelated code.
  static SrcSpan? tryParse(String raw) {
    final span = raw.trim();
    final colon = span.lastIndexOf(':');
    if (colon <= 0 || colon == span.length - 1) return null;
    final file = span.substring(0, colon);
    final range = span.substring(colon + 1);
    final dash = range.indexOf('-');
    final start = _position(dash < 0 ? range : range.substring(0, dash));
    if (start == null) return null;
    final (startLine, startCol) = start;
    if (dash < 0) {
      return SrcSpan(file: file, startLine: startLine, startCol: startCol);
    }
    final end = _position(range.substring(dash + 1));
    if (end == null) return null;
    final (endLine, endCol) = end;
    if (endLine < startLine) return null;
    if (endLine == startLine &&
        startCol != null &&
        endCol != null &&
        endCol < startCol) {
      return null;
    }
    return SrcSpan(
      file: file,
      startLine: startLine,
      startCol: startCol,
      endLine: endLine,
      endCol: endCol,
    );
  }

  /// Every well-formed span in a `|`-joined attribute, in order. Malformed
  /// entries are dropped, so one corrupt span does not lose the rest.
  static List<SrcSpan> parseAll(String? attribute) {
    if (attribute == null || attribute.isEmpty) return const <SrcSpan>[];
    return [
      for (final part in attribute.split('|')) ?tryParse(part),
    ];
  }

  /// `line` or `line.col`, both positive.
  static (int, int?)? _position(String text) {
    if (text.isEmpty) return null;
    final dot = text.indexOf('.');
    final line = _positive(dot < 0 ? text : text.substring(0, dot));
    if (line == null) return null;
    if (dot < 0) return (line, null);
    final col = _positive(text.substring(dot + 1));
    if (col == null) return null;
    return (line, col);
  }

  static int? _positive(String digits) {
    if (digits.isEmpty || digits.length > 9) return null;
    for (final c in digits.codeUnits) {
      if (c < 0x30 || c > 0x39) return null;
    }
    final value = int.parse(digits);
    return value >= 1 ? value : null;
  }

  /// The file exactly as Yosys recorded it.
  final String file;

  /// First line, from 1.
  final int startLine;

  /// First column, from 1, when recorded.
  final int? startCol;

  /// Last line, when the span records a range.
  final int? endLine;

  /// Last column, when the span records a range with columns.
  final int? endCol;

  /// The span in Yosys's own form; [tryParse] reads it back.
  String format() {
    final buffer = StringBuffer('$file:$startLine');
    if (startCol != null) buffer.write('.$startCol');
    if (endLine != null) {
      buffer.write('-$endLine');
      if (endCol != null) buffer.write('.$endCol');
    }
    return buffer.toString();
  }

  /// This span as JSON; [SrcSpan.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'file': file,
    'start_line': startLine,
    if (startCol != null) 'start_col': startCol,
    if (endLine != null) 'end_line': endLine,
    if (endCol != null) 'end_col': endCol,
  };

  @override
  bool operator ==(Object other) =>
      other is SrcSpan &&
      other.file == file &&
      other.startLine == startLine &&
      other.startCol == startCol &&
      other.endLine == endLine &&
      other.endCol == endCol;

  @override
  int get hashCode => Object.hash(file, startLine, startCol, endLine, endCol);

  @override
  String toString() => format();
}

/// The path segments of [path], split on both `/` and `\`, without empty
/// and `.` segments. A drive (`C:`) is a segment like any other.
List<String> _segments(String path) => [
  for (final s in path.split(RegExp(r'[/\\]')))
    if (s.isNotEmpty && s != '.') s,
];

/// How many trailing path segments [a] and [b] share, comparing segment by
/// segment from the file name back. Both path styles are understood on every
/// host, so a span recorded on Windows matches a checkout on Linux.
int sharedPathSuffixLength(String a, String b) {
  final sa = _segments(a);
  final sb = _segments(b);
  var n = 0;
  while (n < sa.length &&
      n < sb.length &&
      sa[sa.length - 1 - n] == sb[sb.length - 1 - n]) {
    n++;
  }
  return n;
}

/// The one file of [designSources] that [recorded] (a path from a `src`
/// span) names, by the longest shared trailing run of path segments; null
/// when none shares even the file name, or when two share the longest run
/// and choosing would be a guess.
///
/// Comparison is exact, segment by segment: `RTL/top.v` and `rtl/top.v`
/// differ.
String? matchSourceBySuffix(String recorded, Iterable<String> designSources) {
  String? best;
  var bestLength = 0;
  var tied = false;
  for (final candidate in designSources) {
    final length = sharedPathSuffixLength(recorded, candidate);
    if (length == 0) continue;
    if (length > bestLength) {
      best = candidate;
      bestLength = length;
      tied = false;
    } else if (length == bestLength && candidate != best) {
      tied = true;
    }
  }
  return tied ? null : best;
}
