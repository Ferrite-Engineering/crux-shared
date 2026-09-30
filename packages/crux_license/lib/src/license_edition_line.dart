// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_status.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// Strings for the one-line edition statement shown in the macOS application
/// menu, above `About <Product>`.
///
/// Separate from the badge strings because this is a sentence rather than a
/// chip, and separate from the panel strings because a product may localize it
/// without pulling in the whole panel.
@immutable
abstract class CruxEditionLineStrings {
  /// Const constructor for subclasses.
  const CruxEditionLineStrings();

  /// `Pro edition — {identity}`, where identity names who the licence is for.
  String editionWithIdentity(String edition, String identity);

  /// `Enterprise edition — licensed by your organization`.
  ///
  /// Used when the licence names nobody. An Enterprise seat licensed from a
  /// policy file has no user email by design, and so does any licence whose
  /// issuer did not record one.
  String editionLicensedByOrganization(String edition);

  /// Display name for the Educational edition.
  String get editionNameEdu;

  /// Display name for the Pro edition.
  String get editionNamePro;

  /// Display name for the Enterprise edition.
  String get editionNameEnterprise;
}

/// English defaults, so a prototype or a test renders without wiring l10n.
class CruxEditionLineStringsEn extends CruxEditionLineStrings {
  /// Creates the default English strings.
  const CruxEditionLineStringsEn();

  @override
  String editionWithIdentity(String edition, String identity) =>
      '$edition edition — $identity';

  @override
  String editionLicensedByOrganization(String edition) =>
      '$edition edition — licensed by your organization';

  @override
  String get editionNameEdu => 'Educational';

  @override
  String get editionNamePro => 'Pro';

  @override
  String get editionNameEnterprise => 'Enterprise';
}

/// The edition line for [status], or `null` when there is nothing to say.
///
/// Returns `null` at Open Core — there is no edition to state, and a menu item
/// reading "Open Core edition" would be chrome advertising the absence of a
/// purchase. Callers render nothing for `null`.
///
/// **Never renders an empty string or the word `null`.** A licence with no
/// recorded identity is the normal Enterprise case rather than an error: a seat
/// licensed from a policy file has no user email by construction. That case
/// says the organization licensed the installation, which is both true and the
/// thing a support call needs to hear.
String? cruxLicenseEditionLine(
  CruxLicenseStatus status,
  CruxEditionLineStrings strings,
) {
  final edition = switch (status.tier) {
    LicenseTier.openCore => null,
    LicenseTier.edu => strings.editionNameEdu,
    LicenseTier.pro => strings.editionNamePro,
    LicenseTier.enterprise => strings.editionNameEnterprise,
  };
  if (edition == null) return null;

  final identity = status.grant?.email?.trim();
  if (identity == null || identity.isEmpty) {
    return strings.editionLicensedByOrganization(edition);
  }
  return strings.editionWithIdentity(edition, identity);
}
