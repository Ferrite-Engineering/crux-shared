// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_policy/crux_policy.dart';
import 'package:crux_policy/src/policy_lint.dart';
import 'package:test/test.dart';

/// `kSuiteKeys`' honoured column, and what reads it.
///
/// The column exists for the administrator who writes a correctly spelled
/// suite key that nothing reads, restarts the application, and believes the
/// restriction it describes is in force. Before it existed the suite block had
/// nowhere to record that a key was dead, so neither the linter nor the
/// startup report could say so even in principle.
void main() {
  DayOnePolicy dayOneWith(String key, Object value) => DayOnePolicy.of(
    PolicyDocument.parse(
      jsonEncode({
        'schema': 1,
        'suite': {key: value},
      }),
    ),
  );

  bool dayOneReads(DayOnePolicy p) =>
      p.telemetry != PolicyTelemetryDecision.absent ||
      p.license != null ||
      p.updateChannel != null ||
      p.pinnedVersion != null ||
      p.manifestUrl != null;

  /// A value each key's own validator accepts, so a key is exercised with
  /// something a reader could act on rather than with junk it rightly ignores.
  const validValues = <String, Object>{
    'telemetry': 'deny',
    'license': {'key': 'key/abc.def'},
    'updateChannel': 'stable',
    'pinnedVersion': '1.0.0',
    'manifestUrl': 'https://mirror.example.internal/manifest.json',
    'audit': {'path': '/var/log/edacrux/audit.jsonl'},
    'theme': 'dark',
    'filePathRestrictions': {
      'deny': ['/secret/**'],
    },
    'plugins': {'allow': <Object>[]},
    'remoteApis': {'wcp': false},
  };

  /// Honoured keys read somewhere other than `DayOnePolicy`, each with where.
  /// An entry here is a claim a test in that package has to keep true.
  const readOutsideDayOne = <String, String>{
    'audit':
        "crux_license's audit-sink binding builds the JSONL sink from it; "
        'policy_binding_test.dart covers it',
  };

  group('the honoured column', () {
    test('names exactly the keys the linter can validate', () {
      // Both directions. A key with a validator and no honoured bit would
      // lint as unknown; one with a bit and no validator could never lint.
      expect(
        kSuiteKeyValidators.keys.toSet(),
        kSuiteKeys.keys.toSet(),
        reason: 'kSuiteKeys and kSuiteKeyValidators must name the same keys',
      );
    });

    test('every key has a valid sample here, so nothing below is vacuous', () {
      expect(validValues.keys.toSet(), kSuiteKeys.keys.toSet());
      for (final entry in validValues.entries) {
        expect(
          kSuiteKeyValidators[entry.key]!(entry.value),
          isTrue,
          reason: 'the sample for ${entry.key} does not validate',
        );
      }
    });

    test('a key marked honoured has a reader', () {
      for (final entry in kSuiteKeys.entries.where((e) => e.value)) {
        final key = entry.key;
        if (readOutsideDayOne.containsKey(key)) continue;
        expect(
          dayOneReads(dayOneWith(key, validValues[key]!)),
          isTrue,
          reason:
              'suite.$key is marked honoured, but DayOnePolicy ignores it and '
              'it is not listed as read elsewhere. Either something reads it '
              'or it is `false`.',
        );
      }
    });

    test('a key marked unhonoured is ignored by the day-one reader', () {
      // The converse. If DayOnePolicy starts reading one of these, the column
      // is now understating what the product does.
      for (final entry in kSuiteKeys.entries.where((e) => !e.value)) {
        expect(
          dayOneReads(dayOneWith(entry.key, validValues[entry.key]!)),
          isFalse,
          reason: 'DayOnePolicy reads suite.${entry.key}; mark it honoured',
        );
      }
    });

    test('every out-of-band reader is still a key, and still honoured', () {
      for (final key in readOutsideDayOne.keys) {
        expect(kSuiteKeys[key], isTrue, reason: key);
      }
    });
  });

  group('crux-policy lint names an unhonoured suite key', () {
    List<PolicyDiagnostic> lint(Map<String, Object?> suite) =>
        lintPolicySource(jsonEncode({'schema': 1, 'suite': suite}));

    test('in the same words as an unhonoured product key', () {
      final suiteFinding = lint({
        'filePathRestrictions': validValues['filePathRestrictions'],
      }).single;
      final productFinding = lintPolicySource(
        jsonEncode({
          'schema': 1,
          'products': {
            'lintcrux': {'mandatoryEngines': <String>[]},
          },
        }),
      ).single;

      expect(suiteFinding.key, 'suite.filePathRestrictions');
      expect(suiteFinding.reason, contains('NOT honoured'));
      expect(suiteFinding.reason, isNot(contains('check the spelling')));
      expect(suiteFinding.reason, productFinding.reason);
    });

    test('every unhonoured key, with a valid value, is named', () {
      for (final key in kSuiteKeys.keys.where((k) => !kSuiteKeys[k]!)) {
        final findings = lint({key: validValues[key]});
        expect(findings.map((f) => f.key), ['suite.$key'], reason: key);
        expect(findings.single.reason, contains('NOT honoured'), reason: key);
      }
    });

    test('an invalid value is reported as well, not instead', () {
      final findings = lint({
        'theme': {'value': 42, 'locked': true},
      });
      expect(findings.map((f) => f.key), ['suite.theme', 'suite.theme']);
      expect(findings.first.reason, contains('not valid'));
      expect(findings.last.reason, contains('NOT honoured'));
    });

    test('an honoured key is silent', () {
      for (final key in kSuiteKeys.keys.where((k) => kSuiteKeys[k]!)) {
        expect(lint({key: validValues[key]}), isEmpty, reason: key);
      }
    });

    test('an unknown key is a spelling prompt, not an unhonoured one', () {
      final finding = lint({'thmee': 'dark'}).single;
      expect(finding.reason, contains('check the spelling'));
      expect(finding.reason, isNot(contains('NOT honoured')));
    });
  });
}
