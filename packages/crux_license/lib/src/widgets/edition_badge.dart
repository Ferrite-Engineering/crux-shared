// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/license_tier_provider.dart';
import 'package:crux_license/src/widgets/feature_tier_badge.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small colored chip stating the edition the user is RUNNING — "you have
/// PRO" — as opposed to what a feature requires.
///
/// **This is the edition badge. [FeatureTierBadge] is the other one.** The
/// suite has two badge concepts, and the names exist to keep them apart:
///
/// - **Feature tier** — [FeatureTierBadge]. Says "this feature requires PRO".
///   Driven by a constructor argument.
/// - **Edition** — `EditionBadge`, this widget. Says "you are running PRO".
///   Driven by `licenseTierProvider`.
///
/// ### Why it reads the provider instead of taking a tier
///
/// A statement about what the user owns has exactly one correct source, and
/// letting a caller pass a different one is a bug waiting to be written — so
/// this reads `licenseTierProvider` directly rather than taking a tier. An
/// EDU-only badge that took its tier as an argument is what this replaced:
/// every call site had to fetch the tier itself, and nothing rendered PRO or
/// ENT anywhere.
///
/// ### Rendering nothing at open core is the load-bearing property
///
/// At [LicenseTier.openCore] this collapses to `SizedBox.shrink()`. That is
/// what makes it safe to mount UNCONDITIONALLY in shared chrome — the status
/// bar's trailing slot, the About dialog — without any call site inspecting
/// the tier first, and without an open-core build advertising an edition it
/// does not have. Test that case before the others.
///
/// ### EDU keeps its own treatment
///
/// EDU renders on `colorScheme.secondary`, its own colour. EDU is not simply
/// "Pro that costs nothing": it carries non-commercial terms and an annual
/// renewal, and that distinction is worth a visual difference.
/// PRO and ENT match [FeatureTierBadge]'s `primary` / `tertiary` so one colour
/// means one tier across both badges.
///
/// [strings] supplies the localized chip labels and screen-reader phrases.
/// The edition semantics are deliberately NOT the feature-tier ones: "Pro
/// edition" and "requires Pro" are different sentences, and a screen-reader
/// user must not hear a feature badge's phrasing for a statement about what
/// they own.
class EditionBadge extends ConsumerWidget {
  /// Creates an edition badge for the tier `licenseTierProvider` resolves to.
  const EditionBadge({
    this.tier,
    this.strings = const LicenseBadgeStringsEn(),
    super.key,
  });

  /// Render this tier instead of reading `licenseTierProvider`.
  ///
  /// **Leave this null almost everywhere.** A statement about what the user
  /// owns has one correct source, and letting callers pass a different one is
  /// how a badge ends up with every call site fetching a tier for itself.
  ///
  /// The one legitimate caller is the licence panel, which is *displaying
  /// licence status* and already holds `status.tier` from
  /// `licenseStatusProvider` — the value `licenseTierProvider` is derived
  /// from, and therefore the more authoritative one in that widget. Passing it
  /// keeps the chip from ever disagreeing with the edition label rendered
  /// immediately beside it.
  final LicenseTier? tier;

  /// Localized strings rendered on the chip. Defaults to English.
  final LicenseBadgeStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Deliberately `?:` and not `??`, for the reason `crux_about_dialog`
    // documents on its own beta-chip override: with `tier ?? ref.watch(...)`
    // the left operand's `LicenseTier?` becomes the context type for the
    // right, so `ref.watch<T>` infers `T = LicenseTier?` (ProviderListenable
    // is covariant) and the whole expression goes nullable. The conditional
    // lets each branch infer independently.
    final resolved = tier == null ? ref.watch(licenseTierProvider) : tier!;
    if (resolved == LicenseTier.openCore) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final (label, semantic, background, foreground) = switch (resolved) {
      LicenseTier.edu => (
        strings.tierBadgeEdu,
        strings.editionBadgeEduSemantic,
        colorScheme.secondary,
        colorScheme.onSecondary,
      ),
      LicenseTier.pro => (
        strings.tierBadgePro,
        strings.editionBadgeProSemantic,
        colorScheme.primary,
        colorScheme.onPrimary,
      ),
      LicenseTier.enterprise => (
        strings.tierBadgeEnterprise,
        strings.editionBadgeEnterpriseSemantic,
        colorScheme.tertiary,
        colorScheme.onTertiary,
      ),
      LicenseTier.openCore => throw StateError('unreachable'),
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
