// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// Localized strings consumed by `CruxLicenseExpiryBanner`.
///
/// Same pattern as `CruxLicensePanelStrings`: the banner belongs to the
/// licence, which only the Pro overlay build carries, so each overlay
/// supplies a subclass backed by its own ARB files through
/// `licenseExpiryStringsProvider`, and [CruxLicenseExpiryStringsEn] renders
/// the widget in a test or an unwired build. None of the strings names a
/// product, so one block of ARB keys serves all four overlays.
///
/// Every `date` argument arrives already formatted, the same way the
/// licence panel formats its state line, so the banner and the panel show
/// the same date.
@immutable
abstract class CruxLicenseExpiryStrings {
  /// Const constructor for subclasses.
  const CruxLicenseExpiryStrings();

  /// Display name of the Educational tier, as the panel shows it.
  String get tierEdu;

  /// Display name of the Pro tier, as the panel shows it.
  String get tierPro;

  /// Display name of the Enterprise tier, as the panel shows it.
  String get tierEnterprise;

  /// A licence of [tier] that expires on [date], inside the warning window.
  String expiringMessage(String tier, String date);

  /// An evaluation of [tier] that ends on [date], inside its shorter window.
  String evaluationEndingMessage(String tier, String date);

  /// A licence of [tier] that expired on [date] and is in its grace period,
  /// with [days] whole days of grace left.
  String graceMessage(String tier, String date, int days);

  /// A licence of [tier] that expired on [date] and whose grace has run out:
  /// the app runs as Open Core, nothing was deleted, and importing a renewed
  /// licence restores the tier at once.
  String endedMessage(String tier, String date);

  /// An evaluation of [tier] that ended on [date]: the app runs as Open
  /// Core, nothing was deleted, and a purchased licence restores the tier.
  String evaluationEndedMessage(String tier, String date);

  /// An evaluation of [tier] stopped because this computer's clock reads
  /// earlier than a time the app has already seen.
  String evaluationClockMessage(String tier);

  /// A licence of [tier] the organization deployed, expiring on [date].
  /// Points at the administrator, never at the purchase page.
  String managedExpiringMessage(String tier, String date);

  /// A licence of [tier] the organization deployed, expired on [date], with
  /// [days] whole days of grace left.
  String managedGraceMessage(String tier, String date, int days);

  /// A licence of [tier] the organization deployed, expired on [date] and
  /// past its grace: the app runs as Open Core.
  String managedEndedMessage(String tier, String date);

  /// Label of the action that opens Settings at the License category.
  String get openSettingsAction;

  /// Label of the action that opens the purchase page, offered when an
  /// evaluation has ended.
  String get buyAction;

  /// Screen-reader name for the trailing dismiss button. Carried by
  /// `Semantics` rather than a `Tooltip`, for the reason given on
  /// `CruxBetaExpiryBanner`: the strip sits above the Navigator's Overlay.
  String get dismissLabel;

  /// The display name for [tier], or an empty string for Open Core, which
  /// never has a notice.
  String tierName(LicenseTier tier) => switch (tier) {
    LicenseTier.edu => tierEdu,
    LicenseTier.pro => tierPro,
    LicenseTier.enterprise => tierEnterprise,
    LicenseTier.openCore => '',
  };
}

/// English [CruxLicenseExpiryStrings] for tests, demos and unwired builds.
@immutable
class CruxLicenseExpiryStringsEn extends CruxLicenseExpiryStrings {
  /// Creates the English default strings.
  const CruxLicenseExpiryStringsEn();

  @override
  String get tierEdu => 'Educational';

  @override
  String get tierPro => 'Pro';

  @override
  String get tierEnterprise => 'Enterprise';

  @override
  String expiringMessage(String tier, String date) =>
      'Your $tier license expires on $date.';

  @override
  String evaluationEndingMessage(String tier, String date) =>
      'Your $tier evaluation ends on $date.';

  @override
  String graceMessage(String tier, String date, int days) =>
      'Your $tier license expired on $date. Features stay on for '
      '${_moreDays(days)}.';

  @override
  String endedMessage(String tier, String date) =>
      'Your $tier license expired on $date and its grace period is over, so '
      'this app now runs as Open Core. Nothing was deleted: import a renewed '
      'license and $tier is back at once.';

  @override
  String evaluationEndedMessage(String tier, String date) =>
      'Your $tier evaluation ended on $date, so this app now runs as Open '
      'Core. Nothing was deleted: import a purchased license and $tier is '
      'back at once.';

  @override
  String evaluationClockMessage(String tier) =>
      "Your $tier evaluation has stopped because this computer's clock reads "
      'earlier than a time this app has already seen. Set the clock to the '
      'correct time, or import a purchased license.';

  @override
  String managedExpiringMessage(String tier, String date) =>
      'The $tier license your organization deployed expires on $date. '
      'Contact your administrator to have it renewed.';

  @override
  String managedGraceMessage(String tier, String date, int days) =>
      'The $tier license your organization deployed expired on $date. '
      'Features stay on for ${_moreDays(days)}; contact your administrator '
      'to have it renewed.';

  @override
  String managedEndedMessage(String tier, String date) =>
      'The $tier license your organization deployed expired on $date, so '
      'this app now runs as Open Core. Nothing was deleted; contact your '
      'administrator to have it renewed.';

  @override
  String get openSettingsAction => 'License settings';

  @override
  String get buyAction => 'Buy a license';

  @override
  String get dismissLabel => 'Dismiss';

  static String _moreDays(int days) =>
      days == 1 ? '1 more day' : '$days more days';
}
