// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by the update banner and the manual
/// "Check for Updates" action.
///
/// `crux_shared` packages carry no ARB files. Each product supplies an
/// `AppLocalizations`-backed subclass mapping every getter to the matching
/// generated string, mirroring the `LicenseBadgeStrings` pattern that
/// `crux_license` establishes and `CruxAboutStrings` follows. The English-only
/// [CruxUpdateStringsEn] default lets prototypes, tests, and demos render the
/// banner without wiring localization first.
///
/// Version interpolation is expressed as a *method* per string that needs it
/// rather than a format template, so a product's ICU placeholder ordering stays
/// entirely inside its own ARB file.
@immutable
abstract class CruxUpdateStrings {
  /// Const constructor for subclasses.
  const CruxUpdateStrings();

  /// Banner message announcing that [version] is available, e.g.
  /// "NetCrux 1.2.0 is available." The product name belongs to the product's
  /// own ARB string; only the version is interpolated here.
  String bannerMessage(String version);

  /// Label of the button that opens the release's changelog URL
  /// (e.g. "View Changes").
  String get viewChangesAction;

  /// Label of the button that opens the download page or app-store listing
  /// (e.g. "Update Now").
  String get updateNowAction;

  /// Accessible name of the banner's dismiss affordance (e.g. "Dismiss").
  /// Rendered as a `Semantics` label — the banner sits above the app's
  /// `Navigator`, so a `Tooltip` would have no `Overlay` ancestor.
  String get dismissLabel;

  /// Transient message shown while a manual check is in flight
  /// (e.g. "Checking for updates…").
  String get checkInProgress;

  /// Manual-check confirmation naming the running [version]
  /// (e.g. "You're on the latest version (1.2.3).").
  String checkUpToDate(String version);

  /// Manual-check failure message (e.g. "Couldn't check for updates.").
  /// Non-fatal — a failed check never breaks a feature flow.
  String get checkFailed;
}

/// Default English [CruxUpdateStrings] used by tests, prototypes, and demos.
///
/// [productName] is interpolated into [bannerMessage]; the default
/// `cruxUpdateStringsProvider` binding fills it from
/// `CruxUpdateConfig.productName`, so an un-overridden build still names the
/// right product.
class CruxUpdateStringsEn extends CruxUpdateStrings {
  /// Creates the default English string set for [productName].
  const CruxUpdateStringsEn({this.productName = 'This application'});

  /// The product display name interpolated into [bannerMessage].
  final String productName;

  @override
  String bannerMessage(String version) => '$productName $version is available.';

  @override
  String get viewChangesAction => 'View Changes';

  @override
  String get updateNowAction => 'Update Now';

  @override
  String get dismissLabel => 'Dismiss';

  @override
  String get checkInProgress => 'Checking for updates…';

  @override
  String checkUpToDate(String version) => version.isEmpty
      ? "You're on the latest version."
      : "You're on the latest version ($version).";

  @override
  String get checkFailed => "Couldn't check for updates.";
}
