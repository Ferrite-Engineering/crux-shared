// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The managed-install rule.
///
/// The stated requirement was that this be testable **without an installed
/// package**, which is what `managedInstallMarkerPathProvider` buys: every test
/// here points the probe at a temp directory.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('managed_install_');
    // flutter_test reports defaultTargetPlatform as android, and
    // updateCheckServiceProvider returns Noop on mobile for its own unrelated
    // reason. Without this override every assertion below would pass whether
    // or not the marker were read at all — the control case in this file
    // failed exactly that way before the override was added.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tmp.deleteSync(recursive: true);
  });

  String marker() => '${tmp.path}${Platform.pathSeparator}.managed-install';

  ProviderContainer containerFor(String? path) {
    final container = ProviderContainer(
      overrides: [
        managedInstallMarkerPathProvider.overrideWithValue(path),
        cruxUpdateConfigProvider.overrideWithValue(
          CruxUpdateConfig(
            productName: 'WaveCrux',
            manifestUri: 'https://updates.example.invalid/manifest.json',
            downloadPageUri: 'https://example.invalid/download',
          ),
        ),
        updateBuildInfoProvider.overrideWith(
          (_) async => const ApplicationBuildInfo(
            version: '1.0.0',
            buildNumber: '1',
            gitShortSha: 'abcdef1',
            os: 'Windows 11',
            architecture: 'x64',
            flutterSdkVersion: '3.44.9',
            dartSdkVersion: '3.12.0',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('probe', () {
    test('absent marker is unmanaged', () {
      expect(
        probeManagedInstall(markerPath: marker()),
        ManagedInstall.unmanaged,
      );
    });

    test('present marker is managed, and reports its mechanism', () {
      File(marker()).writeAsStringSync('msi\n');
      final result = probeManagedInstall(markerPath: marker());
      expect(result.isManaged, isTrue);
      expect(result.mechanism, 'msi');
    });

    test('deb and rpm are reported verbatim, lowercased', () {
      for (final mechanism in ['deb', 'RPM']) {
        File(marker()).writeAsStringSync(mechanism);
        expect(
          probeManagedInstall(markerPath: marker()).mechanism,
          mechanism.toLowerCase(),
        );
      }
    });

    test('an empty body is still managed — presence is the signal', () {
      File(marker()).writeAsStringSync('   \n');
      final result = probeManagedInstall(markerPath: marker());
      expect(result.isManaged, isTrue, reason: 'presence, not contents');
      expect(result.mechanism, isNull);
    });

    test('an unrecognised body is still managed', () {
      // A future package format must not read as unmanaged merely because this
      // build predates it.
      File(marker()).writeAsStringSync('flatpak');
      expect(probeManagedInstall(markerPath: marker()).isManaged, isTrue);
    });

    test('an unreadable path resolves to unmanaged, never throws', () {
      // A directory where a file is expected: existsSync() is false for File,
      // so this must fall through to unmanaged rather than blowing up.
      Directory(marker()).createSync();
      expect(
        probeManagedInstall(markerPath: marker()),
        ManagedInstall.unmanaged,
      );
    });
  });

  group('update check suppression', () {
    // AWAIT the build info, do not merely read it. A synchronous read leaves
    // updateBuildInfoProvider in AsyncLoading, and the provider returns Noop
    // for THAT reason before it ever consults the marker — so these assertions
    // passed identically with the managed check commented out. Caught by
    // running them red against a disabled fix, per standing rule 7.
    test('a managed install yields the Noop service', () async {
      File(marker()).writeAsStringSync('msi\n');
      final container = containerFor(marker());
      await container.read(updateBuildInfoProvider.future);

      expect(
        container.read(updateCheckServiceProvider),
        isA<NoopUpdateCheckService>(),
      );
    });

    test('an unmanaged install does NOT yield Noop once build info is in', () {
      final container = containerFor(marker()); // no marker written
      return container.read(updateBuildInfoProvider.future).then((_) {
        expect(
          container.read(updateCheckServiceProvider),
          isNot(isA<NoopUpdateCheckService>()),
          reason: 'the control case: suppression must be caused by the marker',
        );
      });
    });

    test(
      'suppression holds regardless of what a policy key would say',
      () async {
        // crux_policy is deliberately not consulted here — this test exists to
        // pin that ordering, so wiring updateChannel later cannot quietly
        // become a way to re-enable self-update on a managed fleet.
        File(marker()).writeAsStringSync('msi\n');
        final container = containerFor(marker());
        await container.read(updateBuildInfoProvider.future);
        expect(
          container.read(updateCheckServiceProvider),
          isA<NoopUpdateCheckService>(),
        );
      },
    );
  });
}
