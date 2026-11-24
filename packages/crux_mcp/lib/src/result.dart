// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_mcp/src/document.dart';
import 'package:crux_mcp/src/outcome.dart';
import 'package:meta/meta.dart';

/// What a command wrote with `--json`: the text of its stdout and the
/// outcome that text names.
@immutable
class McpCommandOutput {
  /// The output of a command that built [document]: its [McpDocument.render]
  /// text, byte for byte what the command line writes.
  McpCommandOutput.document(McpDocument document)
    : text = document.render(),
      outcome = document.outcome;

  /// The stdout [text] of a command, read for its outcome by
  /// [mcpDocumentOutcome]. A text that is not a document has no outcome.
  McpCommandOutput.text(this.text) : outcome = mcpDocumentOutcome(text);

  /// Exactly what the command wrote on stdout.
  final String text;

  /// The document's outcome, or null when [text] is not a document.
  final McpOutcome? outcome;

  /// Whether a tool result carrying this output sets `isError`: true for
  /// every outcome that is not an answer, and for a text that is not a
  /// document, which is no answer either.
  bool get isError => outcome?.isError ?? true;

  /// The MCP tool result: `content[0]` is [text] unchanged, and `isError`
  /// is [isError].
  Map<String, Object?> toToolResult() => <String, Object?>{
    'content': <Object?>[
      <String, Object?>{'type': 'text', 'text': text},
    ],
    'isError': isError,
  };
}

/// The outcome [text] names, when it is one document of this format (an
/// object whose `schema_version` is 1 and whose `outcome` is one of the
/// six); otherwise null.
McpOutcome? mcpDocumentOutcome(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  if (decoded['schema_version'] != kMcpDocumentSchemaVersion) return null;
  final outcome = decoded['outcome'];
  return outcome is String ? McpOutcome.fromWireName(outcome) : null;
}
