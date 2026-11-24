// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:test/test.dart';

const _program = McpProgram(name: 'wavecrux', version: '2.0.0');

/// The six outcomes as the JSON contract names them, and which are answers:
/// written from the contract's table, not read from the code under test.
const Map<String, bool> _answers = <String, bool>{
  'completed': true,
  'failed_gate': true,
  'usage_error': false,
  'input_error': false,
  'engine_error': false,
  'licence_error': false,
};

/// The oracle for the decision code that turns an outcome into a result's
/// `isError` and an exit code: every problem it finds with [isErrorOf] and
/// [exitOf] against the contract. Empty when both keep it.
List<String> _outcomeMappingProblems({
  required bool Function(String wireName) isErrorOf,
  required int Function(String wireName) exitOf,
}) {
  final problems = <String>[];
  _answers.forEach((name, answer) {
    if (isErrorOf(name) == answer) {
      problems.add('$name: isError is ${isErrorOf(name)}');
    }
    final code = exitOf(name);
    if ((name == 'completed') != (code == 0)) {
      problems.add('$name exits $code');
    }
  });
  return problems;
}

/// A document of [outcome], as a command would write it, by hand.
String _documentText(String outcome) =>
    '{\n  "schema_version": 1,\n  "tool": {"name": "x", "version": "1"},\n'
    '  "command": "c",\n  "outcome": "$outcome",\n  "engines": [],\n'
    '  "design": null,\n  "body": null,\n  "diagnostics": []\n}\n';

void main() {
  group('McpDocument', () {
    test('writes the eight members in order, null when empty', () {
      const doc = McpDocument(
        tool: _program,
        command: 'transitions',
        outcome: McpOutcome.completed,
        body: <String, Object?>{'window': 1},
      );
      expect(
        doc.render(),
        '{\n'
        '  "schema_version": 1,\n'
        '  "tool": {\n'
        '    "name": "wavecrux",\n'
        '    "version": "2.0.0"\n'
        '  },\n'
        '  "command": "transitions",\n'
        '  "outcome": "completed",\n'
        '  "engines": [],\n'
        '  "design": null,\n'
        '  "body": {\n'
        '    "window": 1\n'
        '  },\n'
        '  "diagnostics": []\n'
        '}\n',
      );
    });

    test('writes engines, design and diagnostics in their member order', () {
      final doc = McpDocument(
        tool: _program,
        command: 'lint',
        outcome: McpOutcome.engineError,
        engines: const <McpEngine>[
          McpEngine(name: 'yosys', version: '0.50', path: '/usr/bin/yosys'),
        ],
        design: const McpDesignFingerprint(scheme: 'sha256', value: 'ab'),
        diagnostics: <McpDiagnostic>[
          McpDiagnostic.error(
            'engine.failed',
            'yosys failed.',
            fix: 'Install it.',
            location: McpSourceLocation(file: '/a.sv', line: 3),
          ),
        ],
      );
      final parsed = jsonDecode(doc.render()) as Map<String, Object?>;
      expect(parsed.keys.toList(), <String>[
        'schema_version',
        'tool',
        'command',
        'outcome',
        'engines',
        'design',
        'body',
        'diagnostics',
      ]);
      expect(parsed['engines'], <Object?>[
        <String, Object?>{
          'name': 'yosys',
          'version': '0.50',
          'path': '/usr/bin/yosys',
        },
      ]);
      expect(parsed['design'], <String, Object?>{
        'fingerprint': <String, Object?>{'scheme': 'sha256', 'value': 'ab'},
      });
      final diagnostic =
          (parsed['diagnostics']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(diagnostic.keys.toList(), <String>[
        'severity',
        'code',
        'message',
        'fix',
        'location',
      ]);
      expect(diagnostic['location'], <String, Object?>{
        'file': '/a.sv',
        'line': 3,
        'column': null,
      });
    });

    test('the usage document says why and carries no body', () {
      final doc = McpDocument.usage(
        tool: _program,
        command: 'info',
        message: 'bad',
      );
      expect(doc.outcome, McpOutcome.usageError);
      expect(doc.body, isNull);
      expect(doc.diagnostics.single.code, 'usage');
      expect(doc.diagnostics.single.severity, McpSeverity.error);
      expect(doc.contractProblems(), isEmpty);
    });

    test('a document that breaks its contract is never written', () {
      const noReason = McpDocument(
        tool: _program,
        command: 'x',
        outcome: McpOutcome.engineError,
      );
      expect(noReason.contractProblems(), isNotEmpty);
      expect(noReason.render, throwsStateError);
      const errorBesideAnswer = McpDocument(
        tool: _program,
        command: 'x',
        outcome: McpOutcome.completed,
        diagnostics: <McpDiagnostic>[McpDiagnostic.error('e', 'm')],
      );
      expect(errorBesideAnswer.render, throwsStateError);
      const badCode = McpDocument(
        tool: _program,
        command: 'x',
        outcome: McpOutcome.completed,
        diagnostics: <McpDiagnostic>[McpDiagnostic.warning('Bad-Code', 'm')],
      );
      expect(badCode.contractProblems(), isNotEmpty);
    });

    test('diagnostic codes are lower-case dotted segments', () {
      expect(McpDiagnostic.codeIsValid('usage'), isTrue);
      expect(McpDiagnostic.codeIsValid('licence.tier_required'), isTrue);
      expect(McpDiagnostic.codeIsValid('fail_on.open2'), isTrue);
      expect(McpDiagnostic.codeIsValid(''), isFalse);
      expect(McpDiagnostic.codeIsValid('a..b'), isFalse);
      expect(McpDiagnostic.codeIsValid('1a'), isFalse);
      expect(McpDiagnostic.codeIsValid('a.B'), isFalse);
    });
  });

  group('outcomes, isError and exit codes', () {
    test('the wire names are the contract six', () {
      expect(
        McpOutcome.values.map((o) => o.wireName).toList(),
        _answers.keys.toList(),
      );
      for (final name in _answers.keys) {
        expect(McpOutcome.fromWireName(name)?.wireName, name);
      }
      expect(McpOutcome.fromWireName('done'), isNull);
    });

    test('the shipped mapping keeps the contract', () {
      final table = McpExitCodes.suite;
      expect(
        _outcomeMappingProblems(
          isErrorOf: (name) => McpOutcome.fromWireName(name)!.isError,
          exitOf: (name) => table.exitCodeFor(McpOutcome.fromWireName(name)!),
        ),
        isEmpty,
      );
    });

    test('a result read from a document text keeps the contract', () {
      expect(
        _outcomeMappingProblems(
          isErrorOf: (name) =>
              McpCommandOutput.text(_documentText(name)).isError,
          exitOf: (name) => McpExitCodes.suite.exitCodeFor(
            mcpDocumentOutcome(_documentText(name))!,
          ),
        ),
        isEmpty,
      );
    });

    test('mutation: an engine_error mapped to completed fails the oracle', () {
      McpOutcome mutant(String name) => name == 'engine_error'
          ? McpOutcome.completed
          : McpOutcome.fromWireName(name)!;
      final problems = _outcomeMappingProblems(
        isErrorOf: (name) => mutant(name).isError,
        exitOf: (name) => McpExitCodes.suite.exitCodeFor(mutant(name)),
      );
      expect(problems, contains('engine_error: isError is false'));
      expect(problems, contains('engine_error exits 0'));
    });

    test('a text that is not a document is an error, never an answer', () {
      for (final text in <String>[
        '',
        'not json',
        '[]',
        '{"outcome": "completed"}',
        '{"schema_version": 2, "outcome": "completed"}',
        '{"schema_version": 1, "outcome": "done"}',
      ]) {
        final output = McpCommandOutput.text(text);
        expect(output.outcome, isNull, reason: text);
        expect(output.isError, isTrue, reason: text);
      }
    });

    test('the tool result carries the text unchanged', () {
      final text = _documentText('failed_gate');
      expect(McpCommandOutput.text(text).toToolResult(), <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
        'isError': false,
      });
    });

    test('a table that lets a failure exit 0 is refused', () {
      expect(
        () => McpExitCodes(
          completed: 0,
          failedGate: 1,
          usageError: 2,
          inputError: 3,
          engineError: 0,
          licenceError: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => McpExitCodes(
          completed: 1,
          failedGate: 1,
          usageError: 2,
          inputError: 3,
          engineError: 4,
          licenceError: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => McpExitCodes(
          completed: 0,
          failedGate: 1,
          usageError: 2,
          inputError: 3,
          engineError: 4,
          licenceError: 256,
        ),
        throwsArgumentError,
      );
    });

    test('the suite table is the convention for new subcommands', () {
      final t = McpExitCodes.suite;
      expect(
        McpOutcome.values.map(t.exitCodeFor).toList(),
        <int>[0, 1, 64, 65, 3, 77],
      );
    });
  });
}
