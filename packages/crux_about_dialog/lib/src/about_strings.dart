// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:meta/meta.dart';

/// Localized strings consumed by `CruxAboutDialog`.
///
/// The widget never bakes in English text. Each product supplies an
/// `AppLocalizations`-backed subclass mapping every getter to the matching
/// ARB-generated string, mirroring the [LicenseBadgeStrings] pattern that
/// `crux_license` already establishes. The English-only [CruxAboutStringsEn]
/// default lets prototypes, tests, and demos render the dialog without wiring
/// localization first.
///
/// Strings here cover only the *chrome* of the dialog (section headers, info
/// row labels, the beta chip, the banner tagline). Product-specific copy — the
/// app name in the title, the tagline, attribution text, action-button labels —
/// is passed directly to `CruxAboutDialog` as data, since those vary per
/// product and are sourced from each product's own ARB files.
@immutable
abstract class CruxAboutStrings {
  /// Const constructor for subclasses.
  const CruxAboutStrings();

  /// Short label shown on the public-beta chip in the header (e.g. "Public
  /// Beta"). Rendered only while the beta-period flag is active.
  String get betaChip;

  /// Header for the version sub-section (e.g. "Version").
  String get sectionVersion;

  /// Row label for the platform build number (e.g. "Build").
  String get buildNumberLabel;

  /// Row label for the short git SHA (e.g. "Commit").
  String get gitShaLabel;

  /// Header for the platform sub-section (e.g. "Platform").
  String get sectionPlatform;

  /// Row label for the host operating system (e.g. "OS").
  String get operatingSystemLabel;

  /// Row label for the CPU architecture (e.g. "Architecture").
  String get architectureLabel;

  /// Row label for the Flutter SDK version (e.g. "Flutter").
  String get flutterVersionLabel;

  /// Row label for the Dart SDK version (e.g. "Dart").
  String get dartVersionLabel;

  /// Snackbar confirmation shown after the "Copy Version Info" action copies
  /// the structured version paragraph to the clipboard.
  String get copiedConfirmation;

  /// Localized strings for the embedded `EditionBadge`. Products return their
  /// existing license-badge-strings adapter so the edition chip in the header
  /// renders the localized label and screen-reader phrase.
  ///
  /// That chip is EDU, PRO *or* ENT, so the adapter must supply the three
  /// `editionBadge*Semantic` phrases as well as the feature-tier ones.
  LicenseBadgeStrings get licenseBadgeStrings;
}

/// Default English [CruxAboutStrings] used by tests, prototypes, and demos.
class CruxAboutStringsEn extends CruxAboutStrings {
  /// Creates the default English string set.
  const CruxAboutStringsEn();

  @override
  String get betaChip => 'Public Beta';

  @override
  String get sectionVersion => 'Version';

  @override
  String get buildNumberLabel => 'Build';

  @override
  String get gitShaLabel => 'Commit';

  @override
  String get sectionPlatform => 'Platform';

  @override
  String get operatingSystemLabel => 'OS';

  @override
  String get architectureLabel => 'Architecture';

  @override
  String get flutterVersionLabel => 'Flutter';

  @override
  String get dartVersionLabel => 'Dart';

  @override
  String get copiedConfirmation => 'Version info copied';

  @override
  LicenseBadgeStrings get licenseBadgeStrings => const LicenseBadgeStringsEn();
}
