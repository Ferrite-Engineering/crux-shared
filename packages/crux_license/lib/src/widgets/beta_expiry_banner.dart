// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/widgets/beta_expiry_banner_strings.dart';
import 'package:flutter/material.dart';

/// Sizing for [CruxBetaExpiryBanner].
///
/// Defaults are the suite-wide desktop values: a 44 dp minimum hit area (the
/// accessibility floor) and a 20 dp icon. WaveCrux is the only product with a
/// device-class metrics system, so it constructs one of these from
/// `MobileMetrics`; the other three take the defaults, which is exactly what
/// their hand-copied constants already said.
@immutable
class CruxBetaExpirySizing {
  /// Creates a sizing override. Every field has a desktop-appropriate default.
  const CruxBetaExpirySizing({
    this.iconSize = 20,
    this.touchTarget = 44,
    this.bodyTextSize,
  });

  /// Edge length of the leading glyph and the dismiss button's icon.
  final double iconSize;

  /// Minimum hit-area edge for the banner's interactive elements. 44 dp is the
  /// suite accessibility floor and applies unchanged on every target.
  final double touchTarget;

  /// Font size for the message. Null (the default) inherits from the theme,
  /// which is what a desktop product wants; WaveCrux passes a device-derived
  /// value so the strip scales with its mobile typography.
  final double? bodyTextSize;
}

/// Dismissible "beta expires soon" strip rendered above the routed app content
/// when a public-beta build is inside the warning window of its hard expiry
/// date (`BetaExpiryStatus.expiringSoon`).
///
/// A dumb leaf widget: it takes the day count, the sizing, the strings and the
/// two callbacks, and renders the strip. The hosting product's beta-expiry gate
/// owns the status and days providers, the dismissal state, and the URL
/// launch — so this widget stays trivially testable without platform channels.
///
/// Lifted into `crux_license` on 2026-08-17. It had been hand-copied into all
/// four products with four different constant-naming conventions
/// (`metrics.iconSize` / `kBetaExpiryIconSize` / `BetaExpiryMetrics.iconSize` /
/// `kBetaExpiryTouchTarget`) — four copies of one cross-product surface where
/// the suite allows one shared implementation. `crux_license` is the right home
/// because it already owns `BetaExpiry`, `BetaPeriod` and their providers.
class CruxBetaExpiryBanner extends StatelessWidget {
  /// Creates the beta-expiry warning strip.
  const CruxBetaExpiryBanner({
    required this.daysRemaining,
    required this.onDownload,
    required this.onDismiss,
    this.strings = const CruxBetaExpiryStringsEn(),
    this.sizing = const CruxBetaExpirySizing(),
    super.key,
  });

  /// Widget key of the dismiss button, so tests can drive it without depending
  /// on the localized semantics label.
  static const Key dismissButtonKey = Key('cruxBetaExpiryBannerDismiss');

  /// Widget key of the inline download action.
  static const Key downloadButtonKey = Key('cruxBetaExpiryBannerDownload');

  /// Whole calendar days remaining until the build expires.
  ///
  /// Always >= 1 here: `0` is `BetaExpiryStatus.expired`, which the product's
  /// blocking overlay handles instead of this strip.
  final int daysRemaining;

  /// Invoked when the user taps the inline download action.
  final VoidCallback onDownload;

  /// Invoked when the user taps the trailing close button to dismiss the strip
  /// for the session.
  final VoidCallback onDismiss;

  /// Localized strings. Defaults to English for tests and demos.
  final CruxBetaExpiryStrings strings;

  /// Sizing overrides. Defaults to the desktop values.
  final CruxBetaExpirySizing sizing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: sizing.iconSize,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.bannerMessage(daysRemaining),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: sizing.bodyTextSize,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: downloadButtonKey,
                onPressed: onDownload,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onTertiaryContainer,
                  minimumSize: Size(sizing.touchTarget, sizing.touchTarget),
                ),
                child: Text(strings.bannerAction),
              ),
              // No Tooltip here: this strip renders *above* the app's Navigator
              // (a sibling of the routed content in `MaterialApp.builder`), so
              // the Navigator's Overlay is not an ancestor and a Tooltip would
              // throw "No Overlay widget found" the moment the banner appears.
              // The accessible name is preserved via Semantics; the close glyph
              // is conventional and the strip's download action carries a
              // visible text label.
              //
              // This is deliberate, load-bearing, and verified correct in all
              // four products. Do not "fix" it into a tooltip.
              Semantics(
                label: strings.dismissLabel,
                button: true,
                child: IconButton(
                  key: dismissButtonKey,
                  onPressed: onDismiss,
                  iconSize: sizing.iconSize,
                  color: scheme.onTertiaryContainer,
                  constraints: BoxConstraints(
                    minWidth: sizing.touchTarget,
                    minHeight: sizing.touchTarget,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
