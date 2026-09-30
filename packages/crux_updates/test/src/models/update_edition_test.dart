// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UpdateInfo release(
    String version, {
    String? openCore,
    bool mandatory = false,
  }) => UpdateInfo(
    version: version,
    openCoreVersion: openCore,
    mandatory: mandatory,
  );

  group('UpdateEdition.of', () {
    test('unlocked paid features map to unlocked', () {
      expect(
        UpdateEdition.of(paidFeaturesUnlocked: true),
        UpdateEdition.unlocked,
      );
    });

    test('no paid features map to openCore', () {
      expect(
        UpdateEdition.of(paidFeaturesUnlocked: false),
        UpdateEdition.openCore,
      );
    });
  });

  group('UpdateEdition.unlocked', () {
    test('is offered a release that changed only paid features', () {
      expect(
        UpdateEdition.unlocked.offers(
          release('1.1.1', openCore: '1.1.0'),
          currentVersion: '1.1.0',
        ),
        isTrue,
      );
    });

    test('is offered a release that declares nothing', () {
      expect(
        UpdateEdition.unlocked.offers(
          release('1.1.1'),
          currentVersion: '1.1.0',
        ),
        isTrue,
      );
    });
  });

  group('UpdateEdition.openCore', () {
    const edition = UpdateEdition.openCore;

    test('is withheld a release when it already has the open-core change', () {
      // 1.1.0 changed open core; 1.1.1 changed only paid features.
      final latest = release('1.1.1', openCore: '1.1.0');
      expect(edition.offers(latest, currentVersion: '1.1.0'), isFalse);
    });

    test('is offered the newest release when it predates the open-core '
        'change, even though that change shipped in an earlier release', () {
      // The case that rules out a per-release "paid only" flag: a seat still
      // on 1.0.0 must hear about 1.1.0's change, and is sent to 1.1.1, which
      // carries it.
      final latest = release('1.1.1', openCore: '1.1.0');
      expect(edition.offers(latest, currentVersion: '1.0.0'), isTrue);
    });

    test('is offered a release that itself changed open core', () {
      final latest = release('1.2.0', openCore: '1.2.0');
      expect(edition.offers(latest, currentVersion: '1.1.1'), isTrue);
    });

    test('is offered a mandatory release that changed only paid features', () {
      final latest = release('1.1.1', openCore: '1.1.0', mandatory: true);
      expect(edition.offers(latest, currentVersion: '1.1.0'), isTrue);
    });

    test('is offered everything when the manifest declares nothing', () {
      expect(edition.offers(release('1.1.1'), currentVersion: '1.1.0'), isTrue);
      expect(
        edition.offers(
          release('1.1.1', openCore: '  '),
          currentVersion: '1.1.0',
        ),
        isTrue,
      );
    });

    test('is offered the release when the declaration is unparseable', () {
      final latest = release('1.1.1', openCore: 'not-a-version');
      expect(edition.offers(latest, currentVersion: '1.1.0'), isTrue);
    });

    test('a pre-release build is older than the open-core release', () {
      final latest = release('1.1.1', openCore: '1.1.0');
      expect(edition.offers(latest, currentVersion: '1.1.0-rc.1'), isTrue);
    });
  });
}
