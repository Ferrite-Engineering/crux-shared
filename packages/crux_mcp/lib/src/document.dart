// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/src/json_writer.dart';
import 'package:crux_mcp/src/location.dart';
import 'package:crux_mcp/src/outcome.dart';
import 'package:meta/meta.dart';

/// The `schema_version` of every document this package writes.
const int kMcpDocumentSchemaVersion = 1;

/// The program that wrote a document: its `tool` member, and the
/// `serverInfo` of its MCP server.
@immutable
class McpProgram implements McpJsonValue {
  /// The program [name] (`wavecrux`, `lintcrux`, ...) at [version].
  const McpProgram({required this.name, required this.version});

  /// The program's name.
  final String name;

  /// Its version.
  final String version;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'version': version,
  };
}

/// An engine a command ran, as it was found.
@immutable
class McpEngine implements McpJsonValue {
  /// The engine [name] at [version], run from [path] when there is a binary.
  const McpEngine({required this.name, required this.version, this.path});

  /// The engine's name.
  final String name;

  /// Its version.
  final String version;

  /// The binary that ran, when there is one.
  final String? path;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'version': version,
    'path': path,
  };
}

/// The fingerprint of an elaborated design: its `design` member.
@immutable
class McpDesignFingerprint implements McpJsonValue {
  /// A [scheme] (such as `sha256`) and its [value].
  const McpDesignFingerprint({required this.scheme, required this.value});

  /// The hash scheme.
  final String scheme;

  /// The hash, as the scheme writes it.
  final String value;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'fingerprint': <String, Object?>{'scheme': scheme, 'value': value},
  };
}

/// How serious a diagnostic is.
enum McpSeverity {
  /// It decided the outcome: the run gave no answer, or a gate fired.
  error,

  /// Worth acting on; the answer stands.
  warning,

  /// For information.
  note,
}

/// One message for a reader: why an outcome is not `completed`, a warning or
/// a note.
@immutable
class McpDiagnostic implements McpJsonValue {
  /// A diagnostic of [severity] with the stable [code] and one sentence
  /// [message], the exact step that fixes it in [fix] when there is one,
  /// and what it points at in [location].
  const McpDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.fix,
    this.location,
  });

  /// An `error` diagnostic.
  const McpDiagnostic.error(
    this.code,
    this.message, {
    this.fix,
    this.location,
  }) : severity = McpSeverity.error;

  /// A `warning` diagnostic.
  const McpDiagnostic.warning(
    this.code,
    this.message, {
    this.fix,
    this.location,
  }) : severity = McpSeverity.warning;

  /// How serious it is.
  final McpSeverity severity;

  /// Stable and machine-readable: segments of lower-case letters, digits and
  /// `_`, each starting with a letter, joined by `.` (`usage`,
  /// `licence.tier_required`).
  final String code;

  /// One sentence for a person.
  final String message;

  /// The exact step that fixes it, when there is one.
  final String? fix;

  /// What it points at, when it points at something.
  final McpLocation? location;

  /// Whether [code] is well formed.
  static bool codeIsValid(String code) =>
      RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$').hasMatch(code);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'severity': severity.name,
    'code': code,
    'message': message,
    'fix': fix,
    'location': location?.toJson(),
  };
}

/// The document every `--json` command writes and every tool returns as its
/// first content item: eight members, always present, in this order, null
/// when empty.
///
/// `schema_version`, `tool`, `command`, `outcome`, `engines`, `design`,
/// `body`, `diagnostics`. A command line writes [render] to stdout and ends
/// with its table's exit code for [outcome]; a server puts the same text in
/// `content[0]`. One writer for both doors is what keeps them the same.
@immutable
class McpDocument {
  /// A document. [body] is the command's own document (a map in member
  /// order, or null when there is no answer).
  const McpDocument({
    required this.tool,
    required this.command,
    required this.outcome,
    this.engines = const <McpEngine>[],
    this.design,
    this.body,
    this.diagnostics = const <McpDiagnostic>[],
  });

  /// The usage error for [command]: outcome `usage_error`, one `usage`
  /// error diagnostic saying [message], no body. Nothing was run.
  factory McpDocument.usage({
    required McpProgram tool,
    required String? command,
    required String message,
  }) => McpDocument(
    tool: tool,
    command: command,
    outcome: McpOutcome.usageError,
    diagnostics: <McpDiagnostic>[McpDiagnostic.error('usage', message)],
  );

  /// The program that wrote it.
  final McpProgram tool;

  /// The command that ran, or null when the arguments named none.
  final String? command;

  /// How the run ended.
  final McpOutcome outcome;

  /// Each engine the command ran.
  final List<McpEngine> engines;

  /// The design analysed, when one is known.
  final McpDesignFingerprint? design;

  /// The command's own document; null when it produced none.
  final Map<String, Object?>? body;

  /// Messages for a reader.
  final List<McpDiagnostic> diagnostics;

  /// The ways this document breaks the contract; empty when it keeps it.
  ///
  /// `completed` carries no error diagnostic; every other outcome carries at
  /// least one, saying why (for `failed_gate`, the gate that fired); every
  /// code is well formed.
  List<String> contractProblems() {
    final problems = <String>[];
    final errors = diagnostics
        .where((d) => d.severity == McpSeverity.error)
        .length;
    if (outcome == McpOutcome.completed && errors > 0) {
      problems.add('a completed outcome carries an error diagnostic');
    }
    if (outcome != McpOutcome.completed && errors == 0) {
      problems.add(
        'outcome ${outcome.wireName} carries no error diagnostic saying why',
      );
    }
    for (final d in diagnostics) {
      if (!McpDiagnostic.codeIsValid(d.code)) {
        problems.add('diagnostic code "${d.code}" is not well formed');
      }
    }
    return problems;
  }

  /// The JSON form, members in the documented order.
  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': kMcpDocumentSchemaVersion,
    'tool': tool.toJson(),
    'command': command,
    'outcome': outcome.wireName,
    'engines': <Object?>[for (final e in engines) e.toJson()],
    'design': design?.toJson(),
    'body': body,
    'diagnostics': <Object?>[for (final d in diagnostics) d.toJson()],
  };

  /// The whole of stdout for `--json`: the document, indented as
  /// [mcpRenderJson] writes it, and one newline.
  ///
  /// Throws a [StateError] when [contractProblems] is not empty: a document
  /// that says `completed` beside an error, or gives no reason for a failure,
  /// is never written.
  String render() {
    final problems = contractProblems();
    if (problems.isNotEmpty) {
      throw StateError('the document breaks its contract: $problems');
    }
    return '${mcpRenderJson(toJson())}\n';
  }
}
