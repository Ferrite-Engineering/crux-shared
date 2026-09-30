// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Where the migration rules are written down: this package's README, as a
/// consuming product's checkout reaches it. Every guard failure points a
/// reader here, because the guard is only the enforcement — the rule itself,
/// and the reasoning behind it, lives in prose.
const String kCruxMigrationGuideRef =
    'crux-shared/packages/crux_sqlite/README.md';

/// One thing a guard found wrong, at one place.
@immutable
final class CruxGuardFinding {
  /// Creates a [CruxGuardFinding].
  const CruxGuardFinding({required this.location, required this.detail});

  /// Where it is, in whatever form a reader can act on: `lib/foo.dart:42`,
  /// or `v3` for a schema version, or a store name.
  final String location;

  /// What is wrong there, in one line.
  final String detail;

  @override
  String toString() => '$location — $detail';
}

/// The result of running one guard over one subject.
///
/// A report is deliberately a value rather than a thrown exception or a
/// direct `expect` call: `crux_sqlite` is pure Dart and has no test framework
/// (see `crux_sqlite_guards.dart`), so the guards compute the verdict and the
/// host repo's thin test decides how to fail. The message a developer reads
/// comes from [describe] either way, so it is identical in both products and
/// in this package's own tests.
@immutable
final class CruxGuardReport {
  /// Creates a [CruxGuardReport].
  const CruxGuardReport({
    required this.guard,
    required this.subject,
    required this.findings,
    required this.whatBroke,
    required this.whyTheRuleExists,
    required this.theWayToGreen,
    this.guideSection = '',
    this.observations = const <CruxGuardFinding>[],
  });

  /// The guard's identity, e.g. `G2 — additive-only monotonicity`.
  final String guard;

  /// What was checked: a store name, or a repo-relative directory.
  final String subject;

  /// Everything wrong. Empty means green.
  final List<CruxGuardFinding> findings;

  /// Things the guard saw and deliberately did not fail on — a sanctioned
  /// delete site, a pinned direct open. Printed in the failure message so a
  /// reader can tell "this is allowed" from "this was missed", and pinned by
  /// the host test so a new one cannot appear silently.
  final List<CruxGuardFinding> observations;

  /// One sentence naming the class of breakage, in the present tense.
  final String whatBroke;

  /// Why the rule exists at all — written for someone who has never heard of
  /// the incident that produced it, because in a year that is everyone.
  final String whyTheRuleExists;

  /// The single legitimate way to make this green. Not a menu: if there were
  /// two, one of them would be the one people pick.
  final String theWayToGreen;

  /// Where in [kCruxMigrationGuideRef] the rule is: a rule number and README
  /// section titles, e.g. `rule 2; "When additive is not enough"`.
  final String guideSection;

  /// Whether nothing is wrong.
  bool get isClean => findings.isEmpty;

  /// The full failure message: what broke, why the rule exists, and the one
  /// legitimate way to make it green.
  ///
  /// Pass this as a test's `reason:`. It is written to be read cold, by
  /// someone who has just had a red CI run on a change they thought was a
  /// schema tidy-up.
  String describe() {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('GUARD $guard')
      ..writeln('  subject: $subject')
      ..writeln()
      ..writeln('WHAT BROKE')
      ..writeln('  $whatBroke');
    for (final finding in findings) {
      buffer
        ..writeln('    • ${finding.location}')
        ..writeln('        ${finding.detail}');
    }
    if (observations.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'ALREADY SANCTIONED (not a failure, listed so you can tell '
          'the difference)',
        );
      for (final observation in observations) {
        buffer
          ..writeln('    • ${observation.location}')
          ..writeln('        ${observation.detail}');
      }
    }
    buffer
      ..writeln()
      ..writeln('WHY THIS RULE EXISTS')
      ..writeln('  $whyTheRuleExists')
      ..writeln()
      ..writeln('THE ONE LEGITIMATE WAY TO MAKE THIS GREEN')
      ..writeln('  $theWayToGreen')
      ..writeln()
      ..writeln(
        '  The rule, and the reasoning behind it: $kCruxMigrationGuideRef'
        '${guideSection.isEmpty ? '' : ' — $guideSection'}',
      )
      ..writeln(
        '  Deleting or loosening a guard is never the fix. If the rule is '
        'wrong,\n  the rule is edited first and the guard follows.',
      );
    return buffer.toString();
  }

  @override
  String toString() => isClean ? 'GUARD $guard: clean ($subject)' : describe();
}
