// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_policy/crux_policy.dart';
import 'package:crux_policy/src/policy_lint.dart';
import 'package:test/test.dart';

/// `lintPolicySource`, in process.
///
/// `cli_test.dart` drives the same linter through the `crux-policy` binary,
/// which is the contract a pipeline sees, but a subprocess reports no coverage
/// and costs a `dart run` per case. These pin every finding the linter can
/// make, one shape each, so a branch that stops firing fails here first.
void main() {
  List<PolicyDiagnostic> lint(Object body) =>
      lintPolicySource(body is String ? body : jsonEncode(body));

  Map<String, String> byKey(List<PolicyDiagnostic> findings) => {
    for (final f in findings) f.key: f.reason,
  };

  group('the file itself', () {
    test('not JSON is one finding, not a throw', () {
      final findings = lint('{"schema": 1,');
      expect(findings.single.key, '<file>');
      expect(findings.single.reason, contains('not valid JSON'));
    });

    test('a top level that is not an object', () {
      expect(lint('[1, 2]').single.reason, 'top level must be an object');
    });

    test('a clean file has no findings', () {
      expect(
        lint({
          'schema': 1,
          'suite': {'telemetry': 'deny'},
          'products': {
            'lintcrux': {'ciGateThreshold': 0},
          },
        }),
        isEmpty,
      );
    });
  });

  group('suite', () {
    test('that is not an object', () {
      expect(byKey(lint({'schema': 1, 'suite': 3})), {
        'suite': 'must be an object',
      });
    });

    test('a value its validator refuses', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'suite': {'telemetry': 'maybe'},
        }),
      );
      expect(findings['suite.telemetry'], contains('is not valid'));
    });

    test('a lock with no value, and a lock that is not a boolean', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'suite': {
            'telemetry': {'locked': true},
            'updateChannel': {'value': 'stable', 'locked': 'yes'},
          },
        }),
      );
      expect(findings['suite.telemetry'], 'has "locked" but no "value"');
      expect(findings['suite.updateChannel'], '"locked" must be a boolean');
    });

    test('pinned needs a pinnedVersion, locked or not', () {
      for (final channel in <Object>[
        'pinned',
        {'value': 'pinned', 'locked': true},
      ]) {
        final findings = byKey(
          lint({
            'schema': 1,
            'suite': {'updateChannel': channel},
          }),
        );
        expect(findings['suite.pinnedVersion'], contains('required'));
      }
      expect(
        lint({
          'schema': 1,
          'suite': {'updateChannel': 'pinned', 'pinnedVersion': '1.0.0'},
        }),
        isEmpty,
      );
    });
  });

  group('suite.audit', () {
    test('a misspelled child key is named, and path is required', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'suite': {
            'audit': {'pth': '/var/log/a.jsonl'},
          },
        }),
      );
      expect(findings['suite.audit.pth'], contains('check the spelling'));
      expect(findings['suite.audit.path'], contains('required'));
    });

    test('an invalid verbosity is named', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'suite': {
            'audit': {'path': '/var/log/a.jsonl', 'verbosity': 'noisy'},
          },
        }),
      );
      expect(findings['suite.audit.verbosity'], contains('is not valid'));
    });

    test('every documented verbosity is accepted', () {
      for (final verbosity in ['off', 'normal', 'verbose']) {
        expect(
          lint({
            'schema': 1,
            'suite': {
              'audit': {'path': '/var/log/a.jsonl', 'verbosity': verbosity},
            },
          }),
          isEmpty,
          reason: verbosity,
        );
      }
    });

    test('a botched lock on a child key is reported once, not validated', () {
      final findings = lint({
        'schema': 1,
        'suite': {
          'audit': {
            'path': {'locked': true},
          },
        },
      });
      final path = findings.where((f) => f.key == 'suite.audit.path');
      expect(path.map((f) => f.reason), ['has "locked" but no "value"']);
    });
  });

  group('products', () {
    test('that is not an object', () {
      expect(byKey(lint({'schema': 1, 'products': 'all'})), {
        'products': 'must be an object',
      });
    });

    test('a product the suite does not have', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'products': {'wavcrux': <String, Object?>{}},
        }),
      );
      expect(findings['products.wavcrux'], contains('almost certainly a typo'));
    });

    test('a product block that is not an object', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'products': {'netcrux': 7},
        }),
      );
      expect(findings['products.netcrux'], 'must be an object');
    });

    test('a misspelled key and an unhonoured key read differently', () {
      final findings = byKey(
        lint({
          'schema': 1,
          'products': {
            'simcrux': {'retentionPolcy': 1, 'defaultSimulator': 'x'},
          },
        }),
      );
      expect(
        findings['products.simcrux.retentionPolcy'],
        contains('check the spelling'),
      );
      expect(
        findings['products.simcrux.defaultSimulator'],
        contains('NOT honoured'),
      );
    });

    test('every registered product key is known to the linter', () {
      for (final product in kProductKeys.keys) {
        for (final entry in kProductKeys[product]!.entries) {
          final findings = lint({
            'schema': 1,
            'products': {
              product: {entry.key: 1},
            },
          });
          expect(
            findings.map((f) => f.reason),
            entry.value ? isEmpty : [contains('NOT honoured')],
            reason: '$product.${entry.key}',
          );
        }
      }
    });
  });
}
