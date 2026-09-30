// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_about_dialog/crux_about_dialog.dart';
// LicenseRegistry / LicenseEntry live in foundation; the asset mock below
// uses only types foundation re-exports.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a fixed asset map through the real rootBundle key path.
void _mockAssets(Map<String, String> assets) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final value = assets[key];
        if (value == null) return null;
        final bytes = Uint8List.fromList(utf8.encode(value));
        return bytes.buffer.asByteData();
      });
}

Future<List<LicenseEntry>> _collect() => LicenseRegistry.licenses.toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LicenseRegistry.reset);

  tearDown(() {
    LicenseRegistry.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('registers a vendored license read from its shipped asset', () async {
    _mockAssets({'assets/elk/LICENSE.epl-2.0.txt': 'Eclipse Public License'});
    registerCruxVendoredLicenses(const [
      CruxVendoredLicense(
        packageName: 'elkjs',
        licenseAssetPath: 'assets/elk/LICENSE.epl-2.0.txt',
      ),
    ]);

    final entries = await _collect();
    expect(entries, hasLength(1));
    expect(entries.single.packages, contains('elkjs'));
    expect(
      entries.single.paragraphs.first.text,
      contains('Eclipse Public License'),
    );
  });

  test('reads the shipped asset rather than a Dart constant, so the '
      'in-app text cannot drift from the redistributed file', () async {
    _mockAssets({'a.txt': 'VERSION FROM THE ASSET'});
    registerCruxVendoredLicenses(const [
      CruxVendoredLicense(packageName: 'p', licenseAssetPath: 'a.txt'),
    ]);

    final entries = await _collect();
    expect(
      entries.single.paragraphs.first.text,
      contains('VERSION FROM THE ASSET'),
    );
  });

  test('registers several components in order', () async {
    _mockAssets({'a.txt': 'A license', 'b.txt': 'B license'});
    registerCruxVendoredLicenses(const [
      CruxVendoredLicense(packageName: 'a', licenseAssetPath: 'a.txt'),
      CruxVendoredLicense(packageName: 'b', licenseAssetPath: 'b.txt'),
    ]);

    final entries = await _collect();
    expect(entries.map((e) => e.packages.first), <String>['a', 'b']);
  });

  test('a missing asset is skipped, not thrown — one typo must not hide '
      'every other attribution behind a broken page', () async {
    _mockAssets({'present.txt': 'Present license'});
    registerCruxVendoredLicenses(const [
      CruxVendoredLicense(packageName: 'missing', licenseAssetPath: 'gone.txt'),
      CruxVendoredLicense(
        packageName: 'present',
        licenseAssetPath: 'present.txt',
      ),
    ]);

    final entries = await _collect();
    expect(entries, hasLength(1));
    expect(entries.single.packages, contains('present'));
  });

  test('an empty asset yields no entry', () async {
    _mockAssets({'blank.txt': '   \n  '});
    registerCruxVendoredLicenses(const [
      CruxVendoredLicense(packageName: 'blank', licenseAssetPath: 'blank.txt'),
    ]);

    expect(await _collect(), isEmpty);
  });

  test('registering an empty list adds no stream at all', () async {
    registerCruxVendoredLicenses(const []);
    expect(await _collect(), isEmpty);
  });
}
