// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A third-party component that ships inside the app but is **not** a pub
/// package, so Flutter's build-time license collection never sees it.
///
/// Flutter assembles `LicenseRegistry` from the `LICENSE` file of every
/// package in the dependency graph. That covers the transitive pub tree
/// automatically and completely — and misses anything vendored: a
/// JavaScript bundle committed under `assets/`, a prebuilt native library,
/// a font. Those are exactly the components whose licenses carry
/// redistribution obligations (EPL-2.0 §3.1(b), ISC, LGPL), so leaving
/// them out of the in-app list is the wrong half to drop.
@immutable
class CruxVendoredLicense {
  /// Describes a vendored component.
  const CruxVendoredLicense({
    required this.packageName,
    required this.licenseAssetPath,
  });

  /// Name shown in the license list (e.g. `elkjs (Eclipse Layout Kernel)`).
  final String packageName;

  /// Flutter asset key of the full license text — the same asset that
  /// satisfies the redistribution obligation. Reading the shipped file
  /// rather than a Dart string constant means the in-app list and the
  /// bundled text cannot drift apart.
  final String licenseAssetPath;
}

/// Registers [licenses] with Flutter's [LicenseRegistry].
///
/// Call once during bootstrap, before any surface that shows a
/// `LicensePage`:
///
/// ```dart
/// registerCruxVendoredLicenses(const [
///   CruxVendoredLicense(
///     packageName: 'elkjs (Eclipse Layout Kernel)',
///     licenseAssetPath: 'assets/elk/LICENSE.epl-2.0.txt',
///   ),
/// ]);
/// ```
///
/// `LicenseRegistry.addLicense` takes a *stream factory*, and Flutter only
/// drains it when the user actually opens the license page — so the asset
/// reads cost nothing at startup.
///
/// A missing or unreadable asset yields no entry rather than throwing. The
/// alternative — crashing the license page because one asset path has a
/// typo — would hide every other attribution behind a broken screen. The
/// asset's presence is better guarded by a static test (see NetCrux's
/// `bundled_license_assets_test.dart`), which fails the build rather than
/// waiting for a user to open the page.
void registerCruxVendoredLicenses(List<CruxVendoredLicense> licenses) {
  if (licenses.isEmpty) return;
  LicenseRegistry.addLicense(() => _vendoredLicenseStream(licenses));
}

Stream<LicenseEntry> _vendoredLicenseStream(
  List<CruxVendoredLicense> licenses,
) async* {
  for (final license in licenses) {
    String text;
    try {
      text = await rootBundle.loadString(license.licenseAssetPath);
    } on Object {
      continue;
    }
    if (text.trim().isEmpty) continue;
    yield LicenseEntryWithLineBreaks(
      <String>[license.packageName],
      text,
    );
  }
}
