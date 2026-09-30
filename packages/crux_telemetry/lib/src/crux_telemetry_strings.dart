// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by the first-launch telemetry disclosure and the
/// Settings → Privacy section.
///
/// `crux_shared` packages carry no ARB files. Each product supplies an
/// `AppLocalizations`-backed subclass mapping every getter to the matching
/// generated string, mirroring the `CruxUpdateStrings` / `LicenseBadgeStrings`
/// pattern. The English-only [CruxTelemetryStringsEn] default lets prototypes,
/// tests and un-localized builds render both surfaces without wiring
/// localization first.
///
/// **The disclosure is deliberately short.** It states the purpose, names what
/// is never taken, and links out; the exhaustive field list and never-collect
/// list live on the suite telemetry page behind [learnMore]. That link is
/// therefore load-bearing rather than decorative — it is where the full
/// disclosure actually lives, so no surface may render this copy without it.
@immutable
abstract class CruxTelemetryStrings {
  /// Const constructor for subclasses.
  const CruxTelemetryStrings();

  // ── The disclosure ─────────────────────────────────────────────────────────

  /// Disclosure title, e.g. "Help make WaveCrux better".
  ///
  /// The product name belongs to the product's own ARB string; nothing is
  /// interpolated here.
  String get consentTitle;

  /// The whole of the disclosure's prose: why the data is wanted, and the
  /// categories that are never taken.
  ///
  /// Names concrete nouns — files, designs, identity — rather than a blanket
  /// "no personally identifiable information" claim. Each clause maps to
  /// something the pipeline verifiably does not carry, which a broader claim
  /// would not.
  String get consentBody;

  /// Label of the link opening the suite disclosure page, e.g. "See exactly
  /// what's collected".
  ///
  /// Shared by the disclosure and by the Settings section's button, so the two
  /// cannot come to describe the same page differently.
  String get learnMore;

  /// Label of the toggle inside the disclosure, e.g. "Share anonymous usage
  /// statistics".
  String get consentToggleLabel;

  /// Label of the disclosure's single confirming button, e.g. "Continue".
  String get consentContinue;

  // ── Settings → Privacy ─────────────────────────────────────────────────────

  /// Title of the Settings telemetry switch.
  String get settingsToggleLabel;

  /// Supporting text under the Settings telemetry switch.
  String get settingsToggleDescription;

  /// Title of the Settings row that links to the disclosure page.
  String get settingsDocsLabel;

  /// Supporting text of the Settings row that links to the disclosure page.
  String get settingsDocsDescription;

  /// Title of the Settings row showing this installation's id.
  String get settingsInstallationIdLabel;

  /// Supporting text explaining what the installation id is for.
  ///
  /// It is the *only* handle on this installation's rows. Nothing collected is
  /// tied to a person, so a deletion request cannot be honoured by looking
  /// somebody up — the user has to be able to read this value and send it.
  /// The privacy policy promises exactly that path, which is why the row is
  /// not optional.
  String get settingsInstallationIdDescription;

  /// Label of the button that copies the installation id.
  String get settingsInstallationIdCopy;

  /// Confirmation shown after the id is copied.
  String get settingsInstallationIdCopied;
}

/// Default English [CruxTelemetryStrings] used by tests, prototypes and
/// un-localized builds.
///
/// [productName] is interpolated into [consentTitle] only; the default
/// `cruxTelemetryStringsProvider` binding fills it from
/// `CruxTelemetryConfig.userAgentName`, so an un-overridden build still names
/// the right product. Every other string is product-neutral by construction —
/// which is also the reason a localized product can map them straight across
/// without rewording.
class CruxTelemetryStringsEn extends CruxTelemetryStrings {
  /// Creates the default English string set for [productName].
  const CruxTelemetryStringsEn({this.productName = 'this application'});

  /// The product display name interpolated into [consentTitle].
  final String productName;

  @override
  String get consentTitle => 'Help make $productName better';

  @override
  String get consentBody =>
      'Anonymous usage and error counts help decide what to build and fix '
      'next. Never your files, your designs, or anything that identifies you.';

  @override
  String get learnMore => "See exactly what's collected";

  @override
  String get consentToggleLabel => 'Share anonymous usage statistics';

  @override
  String get consentContinue => 'Continue';

  @override
  String get settingsToggleLabel => 'Share anonymous usage statistics';

  @override
  String get settingsToggleDescription =>
      'Feature-usage and error counts only. No files, no design data, no '
      'error messages, no personal information.';

  @override
  String get settingsDocsLabel => 'Telemetry disclosure';

  @override
  String get settingsDocsDescription =>
      'The exact field list, the never-collect list, and how to opt out.';

  @override
  String get settingsInstallationIdLabel => 'Installation ID';

  @override
  String get settingsInstallationIdDescription =>
      'The only identifier attached to what is collected. It is random, and '
      'not linked to you. Send it to support if you want the data from this '
      'installation deleted.';

  @override
  String get settingsInstallationIdCopy => 'Copy';

  @override
  String get settingsInstallationIdCopied => 'Installation ID copied.';
}
