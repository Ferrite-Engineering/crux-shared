// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How a command ended: the `outcome` member of every document.
///
/// Two outcomes are answers ([completed], [failedGate]); the other four mean
/// the command produced no answer, and their document carries at least one
/// `error` diagnostic saying why. The document, not the exit code, is the
/// authority.
enum McpOutcome {
  /// The command completed and no gate fired.
  completed('completed'),

  /// The command completed, and a gate the caller asked for fired.
  failedGate('failed_gate'),

  /// Bad arguments or configuration; nothing was run.
  usageError('usage_error'),

  /// The inputs could not be read or used.
  inputError('input_error'),

  /// An engine was missing, failed, timed out or gave an unusable answer.
  engineError('engine_error'),

  /// The licence does not admit what was asked.
  licenceError('licence_error');

  const McpOutcome(this.wireName);

  /// The name in the document.
  final String wireName;

  /// Whether the document holds an answer. Only [completed] and
  /// [failedGate] do.
  bool get isAnswer => this == completed || this == failedGate;

  /// Whether a tool result carrying this outcome sets `isError`: every
  /// outcome that is not an answer.
  bool get isError => !isAnswer;

  /// The outcome named [name] in a document, or null for any other text.
  static McpOutcome? fromWireName(String name) {
    for (final outcome in values) {
      if (outcome.wireName == name) return outcome;
    }
    return null;
  }
}

/// The exit code each outcome ends a command line with.
///
/// Exit codes stay each product's own, because CI scripts branch on them, so
/// every product supplies its table. Two rules hold for every table and the
/// constructor refuses one that breaks them: [McpOutcome.completed] exits 0,
/// and no other outcome does, so an analysis that could not produce an
/// answer never exits 0.
@immutable
class McpExitCodes {
  /// A table. Throws an [ArgumentError] when [completed] is not 0, when any
  /// other code is 0, or when a code is outside 0 to 255.
  McpExitCodes({
    required this.completed,
    required this.failedGate,
    required this.usageError,
    required this.inputError,
    required this.engineError,
    required this.licenceError,
  }) {
    final problems = mcpExitCodeProblems(exitCodeFor);
    if (problems.isNotEmpty) {
      throw ArgumentError(problems.join('; '));
    }
  }

  /// The suite's convention for new subcommands: 0, 1, 64, 65, 3 and 77 for
  /// completed, failed gate, usage, input, engine and licence.
  static final McpExitCodes suite = McpExitCodes(
    completed: 0,
    failedGate: 1,
    usageError: 64,
    inputError: 65,
    engineError: 3,
    licenceError: 77,
  );

  /// Exit code of [McpOutcome.completed].
  final int completed;

  /// Exit code of [McpOutcome.failedGate].
  final int failedGate;

  /// Exit code of [McpOutcome.usageError].
  final int usageError;

  /// Exit code of [McpOutcome.inputError].
  final int inputError;

  /// Exit code of [McpOutcome.engineError].
  final int engineError;

  /// Exit code of [McpOutcome.licenceError].
  final int licenceError;

  /// The exit code for [outcome].
  int exitCodeFor(McpOutcome outcome) => switch (outcome) {
    McpOutcome.completed => completed,
    McpOutcome.failedGate => failedGate,
    McpOutcome.usageError => usageError,
    McpOutcome.inputError => inputError,
    McpOutcome.engineError => engineError,
    McpOutcome.licenceError => licenceError,
  };
}

/// The ways an outcome-to-exit-code mapping breaks the two rules every table
/// keeps; empty when it keeps them.
List<String> mcpExitCodeProblems(int Function(McpOutcome outcome) exitCodeFor) {
  final problems = <String>[];
  for (final outcome in McpOutcome.values) {
    final code = exitCodeFor(outcome);
    if (code < 0 || code > 255) {
      problems.add('${outcome.wireName} exits $code, outside 0 to 255');
    }
    if (outcome == McpOutcome.completed && code != 0) {
      problems.add('completed exits $code, not 0');
    }
    if (outcome != McpOutcome.completed && code == 0) {
      problems.add('${outcome.wireName} exits 0, which only completed may');
    }
  }
  return problems;
}
