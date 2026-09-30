// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/widgets/gated_settings_body.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:crux_license/src/widgets/upgrade_dialog_strings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';

/// Build a tier-gated `pro.*` Settings category for a Pro overlay's
/// `extraSettingsCategories` list.
///
/// The same shape as a plain [CruxSettingsExtraCategory] plus the tier that
/// unlocks it; the body is wrapped in a [CruxGatedSettingsBody] that shows
/// [bodyBuilder]'s widget when the tier allows and the locked panel
/// otherwise. The rail label doubles as the locked panel's feature name, so
/// the two cannot drift apart.
///
/// ```dart
/// cruxGatedSettingsCategory(
///   id: 'pro.collaboration',
///   icon: Icons.groups_outlined,
///   requiredTier: LicenseTier.enterprise,
///   labelBuilder: (context) => L10NPro.of(context).collabSettingsSection,
///   bodyBuilder: (_) => const CollaborationSettingsSection(),
///   badgeStrings: (context) => WaveCruxLicenseBadgeStrings(L10N.of(context)),
///   strings: (context) => WaveCruxUpgradeDialogStrings(
///     L10N.of(context),
///     MaterialLocalizations.of(context).okButtonLabel,
///   ),
/// )
/// ```
///
/// Pass the product's one upgrade-dialog binding, the same adapter its deny
/// path uses, so the locked panel says the dialog's sentence. An overlay never
/// binds a second copy.
///
/// The License category is the one `pro.*` entry that must **not** go
/// through here — see `cruxLicenseSettingsCategory`.
CruxSettingsExtraCategory cruxGatedSettingsCategory({
  required String id,
  required IconData icon,
  required LicenseTier requiredTier,
  required String Function(BuildContext context) labelBuilder,
  required WidgetBuilder bodyBuilder,
  LicenseBadgeStrings Function(BuildContext context)? badgeStrings,
  CruxUpgradeDialogStrings Function(BuildContext context)? strings,
}) => CruxSettingsExtraCategory(
  id: id,
  icon: icon,
  labelBuilder: labelBuilder,
  bodyBuilder: (context) => CruxGatedSettingsBody(
    requiredTier: requiredTier,
    featureName: labelBuilder(context),
    badgeStrings: badgeStrings?.call(context) ?? const LicenseBadgeStringsEn(),
    strings: strings?.call(context) ?? const CruxUpgradeDialogStringsEn(),
    child: bodyBuilder(context),
  ),
);
