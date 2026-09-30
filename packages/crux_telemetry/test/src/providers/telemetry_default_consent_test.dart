// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:ui';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The first-launch default is the product of two seams — the platform's
/// locales and, on the web, its time zone — and this is where they meet.
void main() {
  ProviderContainer containerFor({
    required List<Locale> locales,
    String? timeZone,
  }) {
    final container = ProviderContainer(
      overrides: [
        telemetryPlatformLocalesProvider.overrideWithValue(locales),
        telemetryPlatformTimeZoneProvider.overrideWithValue(timeZone),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('telemetryPlatformTimeZoneProvider', () {
    test('answers null off the web, so desktop is placed by locale alone', () {
      // The VM build of this package resolves to the stub. If this ever
      // answers, an abbreviation has been mistaken for an IANA name.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(telemetryPlatformTimeZoneProvider), isNull);
    });
  });

  group('telemetryDefaultConsentProvider', () {
    const bareEnglish = [Locale('en')];

    test('a country-less locale with a European zone arrives off', () {
      final c = containerFor(locales: bareEnglish, timeZone: 'Europe/Berlin');
      expect(c.read(telemetryDefaultConsentProvider), isFalse);
    });

    test('a country-less locale with no zone arrives on', () {
      final c = containerFor(locales: bareEnglish);
      expect(c.read(telemetryDefaultConsentProvider), isTrue);
    });

    test('a country-less locale with a non-European zone arrives on', () {
      final c = containerFor(locales: bareEnglish, timeZone: 'America/Denver');
      expect(c.read(telemetryDefaultConsentProvider), isTrue);
    });

    test('an opt-in locale arrives off whatever the zone says', () {
      final c = containerFor(
        locales: const [Locale('ko', 'KR')],
        timeZone: 'America/Denver',
      );
      expect(c.read(telemetryDefaultConsentProvider), isFalse);
    });
  });
}
