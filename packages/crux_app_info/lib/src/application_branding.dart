// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Company branding shown in the About box.
///
/// Default value across every product in the suite is the Ferrite Engineering
/// branding. The Riverpod provider in each product is overridable so future
/// white-label deployments can substitute their own company name, logo, and
/// copyright without forking the About-box widget.
@immutable
class ApplicationBranding {
  /// Create a branding record. The logo asset paths point to bundle resources
  /// the consuming Flutter app is responsible for declaring under `assets:`.
  const ApplicationBranding({
    required this.companyName,
    required this.logoAssetPath,
    required this.squareLogoAssetPath,
    required this.copyrightYear,
    required this.websiteUrl,
  });

  /// Company display name (e.g. `Ferrite Engineering`).
  final String companyName;

  /// Asset path for the horizontal-format logo (used in the About-box header).
  final String logoAssetPath;

  /// Asset path for the square-format logo (used in tighter layouts like the
  /// Welcome screen's company chip).
  final String squareLogoAssetPath;

  /// Year (or year range) shown in the copyright notice.
  final String copyrightYear;

  /// Company website URL — opened by the "Visit Website" action button.
  final String websiteUrl;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApplicationBranding &&
        other.companyName == companyName &&
        other.logoAssetPath == logoAssetPath &&
        other.squareLogoAssetPath == squareLogoAssetPath &&
        other.copyrightYear == copyrightYear &&
        other.websiteUrl == websiteUrl;
  }

  @override
  int get hashCode => Object.hash(
    companyName,
    logoAssetPath,
    squareLogoAssetPath,
    copyrightYear,
    websiteUrl,
  );

  @override
  String toString() => 'ApplicationBranding($companyName, $copyrightYear)';
}
