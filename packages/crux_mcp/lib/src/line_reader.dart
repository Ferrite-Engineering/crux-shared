// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crux_mcp/src/protocol.dart';

/// One line read from the input.
sealed class McpInputLine {
  const McpInputLine();
}

/// A line within the limit, without its line ending.
final class McpTextLine extends McpInputLine {
  /// A line holding [text].
  const McpTextLine(this.text);

  /// The decoded line.
  final String text;
}

/// A line past the limit, or one that is not UTF-8. Its bytes are dropped.
final class McpRefusedLine extends McpInputLine {
  /// A refused line; [tooLong] says whether it was past the limit.
  const McpRefusedLine({required this.tooLong});

  /// True for a line past the limit, false for one that is not UTF-8.
  final bool tooLong;
}

/// Splits bytes into lines at `\n`, never holding more than [maxBytes] of
/// one line: a line whose bytes, its newline included, pass [maxBytes] is
/// dropped as it arrives and reported once as [McpRefusedLine]. A last line
/// with no newline is a line too.
Stream<McpInputLine> mcpReadLines(
  Stream<List<int>> input, {
  int maxBytes = kMcpMaxLineBytes,
}) async* {
  final buffer = BytesBuilder(copy: false);
  var length = 0;
  var tooLong = false;
  McpInputLine finish() {
    final bytes = buffer.takeBytes();
    final wasTooLong = tooLong;
    length = 0;
    tooLong = false;
    if (wasTooLong) return const McpRefusedLine(tooLong: true);
    try {
      return McpTextLine(utf8.decode(bytes));
    } on FormatException {
      return const McpRefusedLine(tooLong: false);
    }
  }

  await for (final chunk in input) {
    var start = 0;
    while (start < chunk.length) {
      var newline = -1;
      for (var i = start; i < chunk.length; i++) {
        if (chunk[i] == 0x0A) {
          newline = i;
          break;
        }
      }
      final end = newline == -1 ? chunk.length : newline + 1;
      final count = end - start;
      if (!tooLong) {
        if (length + count > maxBytes) {
          tooLong = true;
          buffer.clear();
        } else {
          // The newline itself is counted, never kept.
          buffer.add(
            chunk.sublist(start, newline == -1 ? end : newline),
          );
        }
      }
      length += count;
      start = end;
      if (newline != -1) yield finish();
    }
  }
  if (length > 0) yield finish();
}
