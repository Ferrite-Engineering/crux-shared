// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Build metadata for the running application instance.
///
/// Populated at startup by each product's `applicationBuildInfoProvider`,
/// which combines `PackageInfo.fromPlatform()` output with compile-time
/// constants injected by CI (`kBuildVersion`, `kBuildNumber`, `kGitSha`).
///
/// Surfaced in the About box and copied to the clipboard via the "Copy
/// Version Info" action — every field is included verbatim in the structured
/// paragraph that ends up in bug reports.
@immutable
class ApplicationBuildInfo {
  /// Create a build info record. All fields are required so the structured
  /// paragraph remains complete; pass `'unknown'` for fields that can't be
  /// determined at runtime rather than leaving them null.
  const ApplicationBuildInfo({
    required this.version,
    required this.buildNumber,
    required this.gitShortSha,
    required this.os,
    required this.architecture,
    required this.flutterSdkVersion,
    required this.dartSdkVersion,
  });

  /// Semantic version string (e.g. `1.2.3`).
  final String version;

  /// Platform-specific build number (CFBundleVersion on iOS, versionCode on
  /// Android, integer-as-string on desktop).
  final String buildNumber;

  /// Short git SHA (typically 7–10 chars) of the commit the build was
  /// produced from.
  final String gitShortSha;

  /// Host operating system, e.g. `macOS 14.5`, `Linux 6.5.0-1018-aws`,
  /// `Windows 11 23H2`, `iOS 17.4`, `Android 14`.
  final String os;

  /// CPU architecture, e.g. `arm64`, `x86_64`.
  final String architecture;

  /// Flutter SDK version (e.g. `3.27.0`).
  final String flutterSdkVersion;

  /// Dart SDK version (e.g. `3.12.0`).
  final String dartSdkVersion;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApplicationBuildInfo &&
        other.version == version &&
        other.buildNumber == buildNumber &&
        other.gitShortSha == gitShortSha &&
        other.os == os &&
        other.architecture == architecture &&
        other.flutterSdkVersion == flutterSdkVersion &&
        other.dartSdkVersion == dartSdkVersion;
  }

  @override
  int get hashCode => Object.hash(
    version,
    buildNumber,
    gitShortSha,
    os,
    architecture,
    flutterSdkVersion,
    dartSdkVersion,
  );

  @override
  String toString() =>
      'ApplicationBuildInfo(version: $version, build: $buildNumber, '
      'sha: $gitShortSha, os: $os, arch: $architecture, '
      'flutter: $flutterSdkVersion, dart: $dartSdkVersion)';
}
