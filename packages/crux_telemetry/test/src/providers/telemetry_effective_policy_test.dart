// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `allow` is not the mirror image of `deny`, and the asymmetry is a compliance
/// constraint rather than an oversight.
///
/// In the EEA, the UK, Switzerland and South Korea the installation id is
/// storage on the user's device that needs consent — ePrivacy Art. 5(3) and its
/// equivalents in Europe, PIPA in Korea — so consent is the only lawful basis
/// there, and **an organization's configuration file is not the user's
/// consent.**
void main() {
  ProviderContainer containerFor({
    required TelemetryPolicy policy,
    required List<Locale> locales,
  }) {
    final container = ProviderContainer(
      overrides: [
        telemetryPolicyProvider.overrideWithValue(policy),
        telemetryPlatformLocalesProvider.overrideWithValue(locales),
        telemetryBetaPeriodProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  const german = [Locale('de', 'DE')];
  const korean = [Locale('ko', 'KR')];
  const american = [Locale('en', 'US')];

  group('deny is unambiguous EVERYWHERE', () {
    for (final (name, locales) in const <(String, List<Locale>)>[
      ('a consent-required region', german),
      ('an opt-out region', american),
    ]) {
      test('in $name it stays deny', () {
        final c = containerFor(policy: TelemetryPolicy.deny, locales: locales);
        expect(c.read(telemetryEffectivePolicyProvider), TelemetryPolicy.deny);
      });
    }
  });

  group('allow is downgraded where consent is the only lawful basis', () {
    test('in the EEA it becomes absent — the config file is not consent', () {
      final c = containerFor(policy: TelemetryPolicy.allow, locales: german);
      expect(
        c.read(telemetryEffectivePolicyProvider),
        TelemetryPolicy.absent,
        reason: 'an organization cannot consent on its employees behalf here',
      );
    });

    test(
      'in South Korea it becomes absent too — outside Europe, same rule',
      () {
        // The region set is not "Europe": Korea's consent-first regime puts it
        // in the same set, and the downgrade has to follow the set, not a
        // continent.
        final c = containerFor(policy: TelemetryPolicy.allow, locales: korean);
        expect(
          c.read(telemetryEffectivePolicyProvider),
          TelemetryPolicy.absent,
        );
        expect(
          c.read(telemetryConsentUiVisibleProvider),
          isTrue,
          reason: 'a downgraded allow must still let the user consent',
        );
      },
    );

    test('elsewhere it means what it says', () {
      final c = containerFor(policy: TelemetryPolicy.allow, locales: american);
      expect(c.read(telemetryEffectivePolicyProvider), TelemetryPolicy.allow);
    });
  });

  group('the gate and the consent surface AGREE', () {
    // If allow closed the consent surface but did not open the gate, a user in
    // a consent-required region could never consent: telemetry would stay off
    // with no way to turn it on, and the organization would believe it was on.
    test('a downgraded allow still OFFERS the consent surface', () {
      final c = containerFor(policy: TelemetryPolicy.allow, locales: german);
      expect(
        c.read(telemetryConsentUiVisibleProvider),
        isTrue,
        reason: 'otherwise the user can never consent',
      );
    });

    test('an honoured allow suppresses the consent surface', () {
      final c = containerFor(policy: TelemetryPolicy.allow, locales: american);
      expect(c.read(telemetryConsentUiVisibleProvider), isFalse);
    });

    test('deny suppresses the consent surface in every region', () {
      for (final locales in const [german, american]) {
        final c = containerFor(policy: TelemetryPolicy.deny, locales: locales);
        expect(c.read(telemetryConsentUiVisibleProvider), isFalse);
      }
    });

    test('absent behaves as if the seam did not exist', () {
      final c = containerFor(policy: TelemetryPolicy.absent, locales: american);
      expect(c.read(telemetryEffectivePolicyProvider), TelemetryPolicy.absent);
      expect(c.read(telemetryConsentUiVisibleProvider), isTrue);
    });
  });
}
