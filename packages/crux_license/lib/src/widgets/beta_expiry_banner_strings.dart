// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by `CruxBetaExpiryBanner`.
///
/// Products supply an `AppLocalizations`-backed subclass so the widget never
/// bakes in English. [CruxBetaExpiryStringsEn] exists so the banner can be
/// dropped into a test or demo without wiring localization first.
///
/// Every product already owns ARB keys for all three of these — the banner was
/// hand-copied into four products before it was lifted here, so adopting this
/// interface is a re-binding, not a translation job.
@immutable
abstract class CruxBetaExpiryStrings {
  /// Const constructor for subclasses.
  const CruxBetaExpiryStrings();

  /// The strip's message, parameterized by whole calendar days remaining.
  ///
  /// Products pass their ARB plural form; [days] is always >= 1 here, because
  /// zero is `BetaExpiryStatus.expired` and gets the blocking overlay instead.
  String bannerMessage(int days);

  /// Label of the inline action that opens the download page.
  String get bannerAction;

  /// Screen-reader name for the trailing dismiss button.
  ///
  /// Carried by `Semantics` rather than a `Tooltip` — see the note on
  /// `CruxBetaExpiryBanner` for why a Tooltip cannot work on this surface.
  String get dismissLabel;
}

/// English-only [CruxBetaExpiryStrings] for tests, demos and prototypes.
@immutable
class CruxBetaExpiryStringsEn extends CruxBetaExpiryStrings {
  /// Creates the English default strings.
  const CruxBetaExpiryStringsEn();

  @override
  String bannerMessage(int days) => days == 1
      ? 'This beta build expires tomorrow.'
      : 'This beta build expires in $days days.';

  @override
  String get bannerAction => 'Download';

  @override
  String get dismissLabel => 'Dismiss';
}
