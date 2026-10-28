// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Pure Dart only: this file is on the `crux_license_core.dart` barrel.

import 'package:crux_license/src/license_status.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// Days before a licence's expiry at which the main window starts saying so.
///
/// Defaults to 30, overridable at build time with
/// `--dart-define=LICENSE_EXPIRY_WARNING_DAYS=<n>`, the same way
/// `BETA_EXPIRY_WARNING_DAYS` moves the beta warning.
const int kLicenseExpiryWarningDays = int.fromEnvironment(
  'LICENSE_EXPIRY_WARNING_DAYS',
  defaultValue: 30,
);

/// Days before an evaluation's end at which the main window starts saying so.
///
/// Shorter than [kLicenseExpiryWarningDays] because evaluations are short: a
/// 30-day countdown on a two-month evaluation would run for half of it.
/// Defaults to 14, overridable with
/// `--dart-define=EVALUATION_EXPIRY_WARNING_DAYS=<n>`.
const int kEvaluationExpiryWarningDays = int.fromEnvironment(
  'EVALUATION_EXPIRY_WARNING_DAYS',
  defaultValue: 14,
);

/// What the main window has to say about a licence's term.
enum CruxLicenseNoticeKind {
  /// Current, and inside the warning window before its expiry.
  expiringSoon,

  /// Past its expiry and inside its grace period: every feature still works.
  inGrace,

  /// Past its expiry and its grace (or an evaluation at its end): the app
  /// now runs as Open Core. Said once, not on every launch.
  ended,
}

/// One notice about a licence's term, for `CruxLicenseExpiryGate`.
@immutable
class CruxLicenseExpiryNotice {
  /// Create a notice.
  const CruxLicenseExpiryNotice({
    required this.kind,
    required this.tier,
    required this.expiry,
    this.licenseId,
    this.graceDaysRemaining,
    this.evaluation = false,
    this.clockSetBack = false,
  });

  /// What the notice says.
  final CruxLicenseNoticeKind kind;

  /// The tier the licence grants, which after the drop to Open Core is the
  /// tier that was lost.
  final LicenseTier tier;

  /// The licence's expiry, or, for an evaluation ended by its clock, the end
  /// date it would otherwise have had.
  final DateTime expiry;

  /// The issuer-side licence id, when the licence names one.
  final String? licenseId;

  /// Whole days of grace left, for [CruxLicenseNoticeKind.inGrace].
  final int? graceDaysRemaining;

  /// Whether the licence is an evaluation.
  final bool evaluation;

  /// Whether an evaluation ended because the clock was set back.
  final bool clockSetBack;

  /// Identifies this notice across rebuilds and launches: the same licence,
  /// term and kind is the same notice. What the one-time memory and the
  /// announce-once rule key on. The day count is left out on purpose, so a
  /// grace countdown crossing midnight is not a new notice.
  String get identity =>
      '${licenseId ?? ''}|${expiry.toUtc().toIso8601String()}|${kind.name}'
      '${clockSetBack ? '|clock' : ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxLicenseExpiryNotice &&
          other.kind == kind &&
          other.tier == tier &&
          other.expiry == expiry &&
          other.licenseId == licenseId &&
          other.graceDaysRemaining == graceDaysRemaining &&
          other.evaluation == evaluation &&
          other.clockSetBack == clockSetBack;

  @override
  int get hashCode => Object.hash(
    kind,
    tier,
    expiry,
    licenseId,
    graceDaysRemaining,
    evaluation,
    clockSetBack,
  );

  @override
  String toString() =>
      'CruxLicenseExpiryNotice(${kind.name}, ${tier.name}, $expiry'
      '${evaluation ? ', evaluation' : ''})';
}

/// The notice [status] calls for at [now], or `null` when there is nothing to
/// say.
///
/// Nothing for Open Core, for a licence with no expiry, for one outside its
/// warning window, and for the states the licence panel already explains
/// (an invalid credential, a refused seat). [now] must be the clock the panel
/// reads, so the banner and the panel agree on the day count: the grace
/// count is [CruxLicenseStatus.graceDaysRemainingAt] itself.
///
/// [warningDays] applies to a paid licence and [evaluationWarningDays] to an
/// evaluation.
CruxLicenseExpiryNotice? cruxLicenseExpiryNoticeFor(
  CruxLicenseStatus status, {
  required DateTime now,
  int warningDays = kLicenseExpiryWarningDays,
  int evaluationWarningDays = kEvaluationExpiryWarningDays,
}) {
  final grant = status.grant;
  final expiry = grant?.expiry;
  if (grant == null || expiry == null) return null;
  CruxLicenseExpiryNotice notice(
    CruxLicenseNoticeKind kind, {
    int? graceDaysRemaining,
  }) => CruxLicenseExpiryNotice(
    kind: kind,
    tier: grant.tier,
    expiry: expiry,
    licenseId: grant.licenseId,
    graceDaysRemaining: graceDaysRemaining,
    evaluation: grant.isEvaluation,
    clockSetBack: status.clockSetBack,
  );
  switch (status.activation) {
    case CruxLicenseActivation.active:
    case CruxLicenseActivation.notActivatedOnThisMachine:
      final lead = Duration(
        days: grant.isEvaluation ? evaluationWarningDays : warningDays,
      );
      final left = expiry.difference(now);
      if (left.isNegative || left > lead) return null;
      return notice(CruxLicenseNoticeKind.expiringSoon);
    case CruxLicenseActivation.grace:
      return notice(
        CruxLicenseNoticeKind.inGrace,
        graceDaysRemaining: status.graceDaysRemainingAt(now) ?? 0,
      );
    case CruxLicenseActivation.expired:
      return notice(CruxLicenseNoticeKind.ended);
    case CruxLicenseActivation.openCore:
    case CruxLicenseActivation.noSeat:
    case CruxLicenseActivation.invalid:
      return null;
  }
}
