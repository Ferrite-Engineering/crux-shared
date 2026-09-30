// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:crux_license/src/widgets/license_panel.dart';
import 'package:crux_license/src/widgets/license_panel_strings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';

/// Rail icon for the License category. A key, because that is the noun the
/// purchase email uses and the thing the user is looking for.
const IconData kCruxLicenseCategoryIcon = Icons.vpn_key_outlined;

/// Build the Settings → License category for a Pro overlay's
/// `extraSettingsCategories` list.
///
/// One line per product, which is the point: the id, the icon and the body
/// are fixed here, so the four overlays cannot drift on any of them.
///
/// ```dart
/// extraSettingsCategoriesProvider.overrideWithValue([
///   cruxLicenseSettingsCategory(
///     product: CruxProduct.waveCrux,
///     strings: (context) => WaveCruxLicensePanelStrings(L10NPro.of(context)),
///     badgeStrings: (context) =>
///         WaveCruxLicenseBadgeStrings(L10N.of(context)),
///   ),
///   // …the product's other pro.* categories
/// ]),
/// ```
///
/// **Never wrap the result in a tier check.** See `CruxLicensePanel` — the
/// category is how a user enters their first key, so gating it on having one
/// is a deadlock, and the seam it arrives through is build-time rather than
/// tier-time.
CruxSettingsExtraCategory cruxLicenseSettingsCategory({
  required CruxProduct product,
  required CruxLicensePanelStrings Function(BuildContext context) strings,
  LicenseBadgeStrings Function(BuildContext context)? badgeStrings,
  Future<String?> Function(BuildContext context)? onPickCredentialFile,
}) => CruxSettingsExtraCategory(
  id: kCruxLicenseCategoryId,
  icon: kCruxLicenseCategoryIcon,
  labelBuilder: (context) => strings(context).licenseCategoryLabel,
  bodyBuilder: (context) => CruxLicensePanel(
    product: product,
    strings: strings(context),
    badgeStrings: badgeStrings?.call(context) ?? const LicenseBadgeStringsEn(),
    onPickCredentialFile: onPickCredentialFile,
  ),
);
