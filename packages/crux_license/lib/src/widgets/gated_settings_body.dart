// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/beta_period_provider.dart';
import 'package:crux_license/src/feature_gate.dart';
import 'package:crux_license/src/license_actions.dart';
import 'package:crux_license/src/license_panel_providers.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/license_tier_provider.dart';
import 'package:crux_license/src/widgets/feature_tier_badge.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:crux_license/src/widgets/upgrade_dialog_strings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The body of a tier-gated Settings category: [child] when the active tier
/// unlocks it, otherwise a locked panel that names the feature, the tier it
/// needs, and — when this build has something to sell — a way to buy it.
///
/// A Pro overlay contributes its `pro.*` categories through a build-time
/// seam: a category is present because the running binary is the Pro overlay,
/// not because the user holds a licence. Every downloader of that binary
/// therefore sees the rail entry at Open Core, and without this widget the
/// detail pane would let them configure a feature the tier gate elsewhere
/// refuses to run. A settings form that accepts edits for a feature the user
/// cannot use reads as "this app is broken", which is worse than a locked
/// panel that says what the feature is and how to get it.
///
/// The gate is the suite-standard one: open while the public beta is on
/// (`betaPeriodProvider`), and otherwise `FeatureGate.satisfiesTier` against
/// `licenseTierProvider`, so EDU unlocks a Pro requirement and Enterprise
/// unlocks everything. Both providers are watched, so activating a licence
/// mid-session swaps the locked panel for the real body without a restart.
///
/// The locked panel reuses the `CruxUpgradeDialog` strings — the rail entry's
/// own label as the feature name, the same `“<feature>” requires <tier>.`
/// sentence — so a product that has already localized the dialog has nothing
/// new to translate. The purchase action comes from `licenseActionsProvider`
/// exactly as the licence panel's Buy button does: one pricing address per
/// product, and no button at all in a build whose actions are
/// [UnsupportedLicenseActions].
///
/// Rendering the locked panel is not a gate *denial* and records no
/// `tier.gate_hit`: the user opened Settings, they did not activate the
/// feature. The activation seams keep that counter.
///
/// **Never wrap the License category in this.** It is how a user enters
/// their first key, so gating it on already having one is a deadlock.
class CruxGatedSettingsBody extends ConsumerWidget {
  /// Creates a gated body around [child].
  const CruxGatedSettingsBody({
    required this.requiredTier,
    required this.featureName,
    required this.child,
    this.badgeStrings = const LicenseBadgeStringsEn(),
    this.strings = const CruxUpgradeDialogStringsEn(),
    super.key,
  });

  /// Minimum tier that unlocks [child] ([LicenseTier.pro] or
  /// [LicenseTier.enterprise]).
  final LicenseTier requiredTier;

  /// Localized name of the gated feature — normally the category's own rail
  /// label, so the locked panel and the rail agree on what this is.
  final String featureName;

  /// The real settings body, rendered only when the tier unlocks it.
  final Widget child;

  /// Localized strings for the [FeatureTierBadge] chip.
  final LicenseBadgeStrings badgeStrings;

  /// Localized strings for the locked panel's sentence and button. Shared
  /// with `CruxUpgradeDialog` on purpose: the two surfaces say the same thing.
  final CruxUpgradeDialogStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked =
        ref.watch(betaPeriodProvider) ||
        FeatureGate.satisfiesTier(requiredTier, ref.watch(licenseTierProvider));
    if (unlocked) return child;

    final seePricing = cruxSeePricingAction(ref.watch(licenseActionsProvider));
    final tierName = switch (requiredTier) {
      LicenseTier.enterprise => strings.tierNameEnterprise,
      LicenseTier.pro ||
      LicenseTier.edu ||
      LicenseTier.openCore => strings.tierNamePro,
    };
    final theme = Theme.of(context);
    return CruxSettingsSectionCard(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(featureName, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(width: 8),
            FeatureTierBadge(requiredTier: requiredTier, strings: badgeStrings),
          ],
        ),
        const SizedBox(height: 12),
        Text(strings.body(featureName, tierName)),
        if (seePricing != null) ...<Widget>[
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              onPressed: seePricing,
              child: Text(strings.seePricingLabel),
            ),
          ),
        ],
      ],
    );
  }
}
