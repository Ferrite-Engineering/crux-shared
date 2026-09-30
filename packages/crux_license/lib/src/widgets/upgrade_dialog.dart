// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart' show ModalGuard;
import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/widgets/feature_tier_badge.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:crux_license/src/widgets/upgrade_dialog_strings.dart';
import 'package:flutter/material.dart';

/// The suite-standard upgrade-required dialog shown when a Pro/Enterprise
/// action is activated under a license tier that does not include it.
///
/// This is the suite's gate-denial convention: tier-gated items stay
/// enabled and tier-badged on every discovery surface, and an
/// insufficient-tier *activation* surfaces this dialog instead of a silent
/// no-op — the user learns why nothing happened and which tier unlocks the
/// feature. During the public beta the gate short-circuits to allow, so
/// the dialog is unreachable until the beta flip.
///
/// Deliberately small: a title with a [FeatureTierBadge], a body naming the
/// feature and the required tier, an optional supplemental line, a dismiss
/// button, and — when the caller supplies one — a way to buy the tier being
/// asked for.
///
/// **The purchase action exists because there is something to buy**; it was
/// absent while there was not. A dialog that says a feature needs Pro and then
/// offers no way to get Pro is a dead end, and this is the single moment in
/// the product where a user is most willing to act on it. Still optional: a
/// build with no commerce wiring renders dismiss alone rather than a button
/// that goes nowhere.
///
/// All text comes from the caller-supplied [CruxUpgradeDialogStrings] and
/// [LicenseBadgeStrings]; products pass `AppLocalizations`-backed
/// subclasses so the dialog never bakes in English. What those strings may
/// say is a suite contract, documented on [CruxUpgradeDialogStrings].
///
/// Open it through [show], never a bare `showDialog`: [show] is the one
/// opener, and it is re-entrancy guarded.
class CruxUpgradeDialog extends StatelessWidget {
  /// Creates the dialog. Prefer the [show] launcher at call sites.
  const CruxUpgradeDialog({
    required this.featureName,
    required this.requiredTier,
    required this.strings,
    required this.l10n,
    this.supplementalMessage,
    this.onSeePricing,
    super.key,
  });

  /// Localized label of the action the user activated.
  final String featureName;

  /// Minimum tier that unlocks the action ([LicenseTier.pro] or
  /// [LicenseTier.enterprise]).
  final LicenseTier requiredTier;

  /// Localized strings for the [FeatureTierBadge] chip in the title.
  final LicenseBadgeStrings strings;

  /// Localized strings for the dialog's title, body, and dismiss button.
  final CruxUpgradeDialogStrings l10n;

  /// Optional extra line rendered under the body — e.g. a product-specific
  /// note about where to manage the license. Omitted when null.
  final String? supplementalMessage;

  /// Opens the pricing page. When null the action is not rendered at all.
  ///
  /// Products pass `ref.read(licenseActionsProvider).openPurchasePage`, which
  /// is the same URL the licence panel's own Buy button uses — so there is one
  /// pricing address per product rather than one per call site.
  final Future<void> Function()? onSeePricing;

  /// The [ModalGuard] key [show] holds while an upgrade dialog is open.
  ///
  /// One key for every upgrade dialog, whatever the feature: a second denial
  /// while the first dialog is still up has nothing new to say.
  static const String modalGuardKey = 'crux_license.upgrade_dialog';

  /// Shows the dialog over [context]. Resolves when it is dismissed.
  ///
  /// Re-entrancy guarded with [ModalGuard] under [modalGuardKey]. A gated
  /// action is usually shortcut-reachable, and the app's shortcut layer sits
  /// above the `Navigator`: holding the chord (key auto-repeat) or pressing it
  /// again re-dispatches the denial while the dialog is already open. Without
  /// the guard each dispatch stacks another copy. A suppressed call resolves
  /// immediately. Guarding here rather than in each product's wrapper is what
  /// covers every caller, including ones not yet written.
  static Future<void> show(
    BuildContext context, {
    required String featureName,
    required LicenseTier requiredTier,
    required LicenseBadgeStrings strings,
    required CruxUpgradeDialogStrings l10n,
    String? supplementalMessage,
    Future<void> Function()? onSeePricing,
  }) {
    return ModalGuard.run(
      modalGuardKey,
      () => showDialog<void>(
        context: context,
        builder: (_) => CruxUpgradeDialog(
          featureName: featureName,
          requiredTier: requiredTier,
          strings: strings,
          l10n: l10n,
          supplementalMessage: supplementalMessage,
          onSeePricing: onSeePricing,
        ),
      ),
    );
  }

  /// [featureName] as it reads inside a sentence.
  ///
  /// Products name the feature with the label of the control the user
  /// activated, and a menu or palette label that opens further UI ends in an
  /// ellipsis ("Switch Project…"). That ellipsis means "more to come" on the
  /// control; quoted in prose it is noise, so it is dropped here, once, for
  /// every product.
  static String _featureNameInProse(String featureName) {
    final trimmed = featureName.trimRight();
    if (trimmed.endsWith('…')) {
      return trimmed.substring(0, trimmed.length - 1).trimRight();
    }
    if (trimmed.endsWith('...')) {
      return trimmed.substring(0, trimmed.length - 3).trimRight();
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    // EDU is feature-equivalent to Pro, so a gate that names edu (or, by
    // defensive fallback, openCore) reads as the Pro tier in the body.
    final tierName = switch (requiredTier) {
      LicenseTier.enterprise => l10n.tierNameEnterprise,
      LicenseTier.pro ||
      LicenseTier.edu ||
      LicenseTier.openCore => l10n.tierNamePro,
    };
    final supplemental = supplementalMessage;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Expanded(child: Text(l10n.title)),
          FeatureTierBadge(requiredTier: requiredTier, strings: strings),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.body(_featureNameInProse(featureName), tierName)),
          if (supplemental != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(supplemental),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.dismissLabel),
        ),
        if (onSeePricing != null)
          FilledButton(
            onPressed: () async {
              // Dismiss first: the pricing page opens in the browser, and
              // leaving a modal behind it means the user comes back to a
              // dialog they already dealt with.
              await Navigator.of(context).maybePop();
              await onSeePricing!();
            },
            child: Text(l10n.seePricingLabel),
          ),
      ],
    );
  }
}
