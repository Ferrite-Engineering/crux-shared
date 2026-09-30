// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/widgets/edition_badge.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:flutter/material.dart';

/// Small colored chip displayed next to a FEATURE that requires a higher
/// product tier than [LicenseTier.openCore] — "this needs PRO/ENT".
///
/// **This is the feature-tier badge. [EditionBadge] is the other one.** The
/// suite has two badge concepts, and the names exist to keep them apart:
///
/// - **Feature tier** — `FeatureTierBadge`, this widget. Says "this feature
///   requires PRO". Driven by a constructor argument: the tier the FEATURE
///   needs.
/// - **Edition** — [EditionBadge]. Says "you are running PRO". Driven by
///   `licenseTierProvider`: the tier the USER has.
///
/// The suite keeps the two apart deliberately. This one takes its tier as an
/// argument precisely because it is a property of the feature, not of the user:
/// a screenshot of the toolbar shows the same `PRO` chip whether or not the
/// person looking at it has bought anything.
///
/// Renders as `PRO` or `ENT` depending on [requiredTier]. Open-core features
/// pass [LicenseTier.openCore] and the badge collapses to a zero-size
/// `SizedBox.shrink()` — making it safe to wrap every feature surface
/// unconditionally without runtime tier inspection at the call site.
///
/// **Educational tier ([LicenseTier.edu]) is not a feature-required tier:**
/// every feature available to EDU is also available to Pro, so feature
/// labels should use [LicenseTier.pro] as their required tier rather than
/// EDU. If [LicenseTier.edu] is passed regardless, this widget collapses
/// to a zero-size `SizedBox.shrink()` (same as openCore) since labeling a
/// feature as "EDU-required" is semantically meaningless. The user-facing
/// EDU edition badge for the About box / Welcome screen is rendered by
/// [EditionBadge] instead.
///
/// The badge is communication, not enforcement: it is visible during the
/// public beta as well as post-beta, so users learn the tier boundary before
/// it starts costing them anything. Activation gating is a separate concern,
/// handled by `FeatureGate`.
///
/// [strings] supplies the localized chip labels and screen-reader phrases.
/// Products pass a subclass of [LicenseBadgeStrings] backed by their
/// `AppLocalizations`; the default [LicenseBadgeStringsEn] returns English
/// text so prototypes, tests, and demos render without wiring localization
/// first.
class FeatureTierBadge extends StatelessWidget {
  /// Creates a tier badge labeling a feature that requires [requiredTier].
  const FeatureTierBadge({
    required this.requiredTier,
    this.strings = const LicenseBadgeStringsEn(),
    super.key,
  });

  /// The minimum tier required to use the feature this badge labels.
  final LicenseTier requiredTier;

  /// Localized strings rendered on the chip. Defaults to English.
  final LicenseBadgeStrings strings;

  @override
  Widget build(BuildContext context) {
    if (requiredTier == LicenseTier.openCore ||
        requiredTier == LicenseTier.edu) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final (label, semantic, background, foreground) = switch (requiredTier) {
      LicenseTier.pro => (
        strings.tierBadgePro,
        strings.tierBadgeProSemantic,
        colorScheme.primary,
        colorScheme.onPrimary,
      ),
      LicenseTier.enterprise => (
        strings.tierBadgeEnterprise,
        strings.tierBadgeEnterpriseSemantic,
        colorScheme.tertiary,
        colorScheme.onTertiary,
      ),
      LicenseTier.openCore ||
      LicenseTier.edu => throw StateError('unreachable'),
    };
    return Semantics(
      label: semantic,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
