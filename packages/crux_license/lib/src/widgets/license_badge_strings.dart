// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by `FeatureTierBadge` and `EditionBadge`.
///
/// Products supply an `AppLocalizations`-backed subclass that maps each
/// getter to the appropriate ARB-generated string so the widgets never
/// bake in English text. The English-only [LicenseBadgeStringsEn] default
/// is provided so callers can drop the widgets into a prototype, test, or
/// demo without wiring localization first. Every field is an abstract
/// getter so a future ARB-generated implementation can slot in without
/// changing call sites.
///
/// Strings are paired into a label / semantic label per tier so screen
/// readers receive a phrase a human would expect ("Pro tier feature")
/// rather than the bare chip label ("PRO").
@immutable
abstract class LicenseBadgeStrings {
  /// Const constructor for subclasses.
  const LicenseBadgeStrings();

  // --- Tier badge -----------------------------------------------------

  /// Short visual label for the Pro-tier badge chip (e.g. "PRO").
  String get tierBadgePro;

  /// Screen-reader phrase rendered on the Pro-tier badge chip.
  String get tierBadgeProSemantic;

  /// Short visual label for the Enterprise-tier badge chip (e.g. "ENT").
  String get tierBadgeEnterprise;

  /// Screen-reader phrase rendered on the Enterprise-tier badge chip.
  String get tierBadgeEnterpriseSemantic;

  // --- Edition badge ---------------------------------------------------

  /// Short visual label for the Educational edition badge chip (e.g. "EDU").
  String get tierBadgeEdu;

  /// Screen-reader phrase for the Educational badge where it labels a
  /// *feature*. Retained for callers that still label EDU-specific surfaces.
  String get tierBadgeEduSemantic;

  // The three below are EDITION semantics — what the user IS RUNNING — and are
  // deliberately separate from the feature-tier phrases above. "Pro edition"
  // and "requires Pro" are different sentences, and a screen-reader user must
  // not hear the second when the screen is saying the first.

  /// Screen-reader phrase for the badge stating the user runs Educational.
  String get editionBadgeEduSemantic;

  /// Screen-reader phrase for the badge stating the user runs Pro.
  String get editionBadgeProSemantic;

  /// Screen-reader phrase for the badge stating the user runs Enterprise.
  String get editionBadgeEnterpriseSemantic;
}

/// Default English [LicenseBadgeStrings] used when callers do not supply
/// their own. Mirrors the strings products typically pull from their ARB
/// files.
class LicenseBadgeStringsEn extends LicenseBadgeStrings {
  /// Creates the default English string set.
  const LicenseBadgeStringsEn();

  @override
  String get tierBadgePro => 'PRO';

  @override
  String get tierBadgeProSemantic => 'Pro tier feature';

  @override
  String get tierBadgeEnterprise => 'ENT';

  @override
  String get tierBadgeEnterpriseSemantic => 'Enterprise tier feature';

  @override
  String get tierBadgeEdu => 'EDU';

  @override
  String get tierBadgeEduSemantic => 'Educational license';

  @override
  String get editionBadgeEduSemantic => 'Educational edition';

  @override
  String get editionBadgeProSemantic => 'Pro edition';

  @override
  String get editionBadgeEnterpriseSemantic => 'Enterprise edition';
}
