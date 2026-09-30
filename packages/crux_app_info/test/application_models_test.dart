// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:test/test.dart';

/// Both types in this package are immutable value objects handed to Riverpod
/// providers, which dedupe rebuilds with `==`. An `==` that ignores a field
/// therefore does not fail loudly — it silently stops the UI updating when
/// that field changes. So every field is exercised individually, in both
/// directions, rather than spot-checked.
void main() {
  const buildInfo = ApplicationBuildInfo(
    version: '1.2.3',
    buildNumber: '456',
    gitShortSha: 'abc1234',
    os: 'macOS 14.5',
    architecture: 'arm64',
    flutterSdkVersion: '3.27.0',
    dartSdkVersion: '3.12.0',
  );

  const branding = ApplicationBranding(
    companyName: 'Ferrite Engineering',
    logoAssetPath: 'assets/branding/ferrite_engineering_logo.svg',
    squareLogoAssetPath: 'assets/branding/ferrite_engineering_square.svg',
    copyrightYear: '2026',
    websiteUrl: 'https://ferriteengineering.com',
  );

  group('ApplicationBuildInfo', () {
    test('exposes all build fields', () {
      expect(buildInfo.version, '1.2.3');
      expect(buildInfo.buildNumber, '456');
      expect(buildInfo.gitShortSha, 'abc1234');
      expect(buildInfo.os, 'macOS 14.5');
      expect(buildInfo.architecture, 'arm64');
      expect(buildInfo.flutterSdkVersion, '3.27.0');
      expect(buildInfo.dartSdkVersion, '3.12.0');
    });

    test('is equal to an identically-valued instance', () {
      const same = ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: '456',
        gitShortSha: 'abc1234',
        os: 'macOS 14.5',
        architecture: 'arm64',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: '3.12.0',
      );
      expect(buildInfo, equals(same));
      expect(buildInfo.hashCode, same.hashCode);
    });

    test('takes the identity short-circuit for the same instance', () {
      const Object self = buildInfo;
      expect(buildInfo == self, isTrue);
    });

    test('is never equal to an instance of another type', () {
      const Object other = branding;
      expect(buildInfo == other, isFalse);
      expect(buildInfo == Object(), isFalse);
    });

    // Each entry mutates exactly one field. A field missing from `==` or
    // `hashCode` fails the corresponding case and no other.
    final variants = <String, ApplicationBuildInfo>{
      'version': const ApplicationBuildInfo(
        version: 'X',
        buildNumber: '456',
        gitShortSha: 'abc1234',
        os: 'macOS 14.5',
        architecture: 'arm64',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: '3.12.0',
      ),
      'buildNumber': const ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: 'X',
        gitShortSha: 'abc1234',
        os: 'macOS 14.5',
        architecture: 'arm64',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: '3.12.0',
      ),
      'gitShortSha': const ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: '456',
        gitShortSha: 'X',
        os: 'macOS 14.5',
        architecture: 'arm64',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: '3.12.0',
      ),
      'os': const ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: '456',
        gitShortSha: 'abc1234',
        os: 'X',
        architecture: 'arm64',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: '3.12.0',
      ),
      'architecture': const ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: '456',
        gitShortSha: 'abc1234',
        os: 'macOS 14.5',
        architecture: 'X',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: '3.12.0',
      ),
      'flutterSdkVersion': const ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: '456',
        gitShortSha: 'abc1234',
        os: 'macOS 14.5',
        architecture: 'arm64',
        flutterSdkVersion: 'X',
        dartSdkVersion: '3.12.0',
      ),
      'dartSdkVersion': const ApplicationBuildInfo(
        version: '1.2.3',
        buildNumber: '456',
        gitShortSha: 'abc1234',
        os: 'macOS 14.5',
        architecture: 'arm64',
        flutterSdkVersion: '3.27.0',
        dartSdkVersion: 'X',
      ),
    };

    for (final entry in variants.entries) {
      test('differs when only ${entry.key} differs', () {
        expect(buildInfo, isNot(equals(entry.value)));
        expect(buildInfo.hashCode, isNot(entry.value.hashCode));
      });
    }

    test('toString reports every field', () {
      expect(
        buildInfo.toString(),
        'ApplicationBuildInfo(version: 1.2.3, build: 456, sha: abc1234, '
        'os: macOS 14.5, arch: arm64, flutter: 3.27.0, dart: 3.12.0)',
      );
    });
  });

  group('ApplicationBranding', () {
    test('exposes all branding fields', () {
      expect(branding.companyName, 'Ferrite Engineering');
      expect(
        branding.logoAssetPath,
        'assets/branding/ferrite_engineering_logo.svg',
      );
      expect(
        branding.squareLogoAssetPath,
        'assets/branding/ferrite_engineering_square.svg',
      );
      expect(branding.copyrightYear, '2026');
      expect(branding.websiteUrl, 'https://ferriteengineering.com');
    });

    test('is equal to an identically-valued instance', () {
      const same = ApplicationBranding(
        companyName: 'Ferrite Engineering',
        logoAssetPath: 'assets/branding/ferrite_engineering_logo.svg',
        squareLogoAssetPath: 'assets/branding/ferrite_engineering_square.svg',
        copyrightYear: '2026',
        websiteUrl: 'https://ferriteengineering.com',
      );
      expect(branding, equals(same));
      expect(branding.hashCode, same.hashCode);
    });

    test('takes the identity short-circuit for the same instance', () {
      const Object self = branding;
      expect(branding == self, isTrue);
    });

    test('is never equal to an instance of another type', () {
      const Object other = buildInfo;
      expect(branding == other, isFalse);
      expect(branding == Object(), isFalse);
    });

    final variants = <String, ApplicationBranding>{
      'companyName': const ApplicationBranding(
        companyName: 'Acme',
        logoAssetPath: 'assets/branding/ferrite_engineering_logo.svg',
        squareLogoAssetPath: 'assets/branding/ferrite_engineering_square.svg',
        copyrightYear: '2026',
        websiteUrl: 'https://ferriteengineering.com',
      ),
      'logoAssetPath': const ApplicationBranding(
        companyName: 'Ferrite Engineering',
        logoAssetPath: 'assets/other.svg',
        squareLogoAssetPath: 'assets/branding/ferrite_engineering_square.svg',
        copyrightYear: '2026',
        websiteUrl: 'https://ferriteengineering.com',
      ),
      'squareLogoAssetPath': const ApplicationBranding(
        companyName: 'Ferrite Engineering',
        logoAssetPath: 'assets/branding/ferrite_engineering_logo.svg',
        squareLogoAssetPath: 'assets/other_square.svg',
        copyrightYear: '2026',
        websiteUrl: 'https://ferriteengineering.com',
      ),
      'copyrightYear': const ApplicationBranding(
        companyName: 'Ferrite Engineering',
        logoAssetPath: 'assets/branding/ferrite_engineering_logo.svg',
        squareLogoAssetPath: 'assets/branding/ferrite_engineering_square.svg',
        copyrightYear: '2027',
        websiteUrl: 'https://ferriteengineering.com',
      ),
      'websiteUrl': const ApplicationBranding(
        companyName: 'Ferrite Engineering',
        logoAssetPath: 'assets/branding/ferrite_engineering_logo.svg',
        squareLogoAssetPath: 'assets/branding/ferrite_engineering_square.svg',
        copyrightYear: '2026',
        websiteUrl: 'https://example.com',
      ),
    };

    for (final entry in variants.entries) {
      test('differs when only ${entry.key} differs', () {
        expect(branding, isNot(equals(entry.value)));
        expect(branding.hashCode, isNot(entry.value.hashCode));
      });
    }

    test('toString reports the company and copyright year', () {
      expect(
        branding.toString(),
        'ApplicationBranding(Ferrite Engineering, 2026)',
      );
    });
  });
}
