// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the opt-in country set', () {
    test('covers the EEA, the UK, Switzerland and South Korea, and nothing '
        'else', () {
      // The consent-first rule names these groups and overrides default-on for
      // them and nowhere else. A country arriving here by accident would
      // silently cost measurement in a region entitled to none of this
      // protection, which is the failure this asserts against.
      expect(kTelemetryOptInCountries, hasLength(33));

      const eu27 = <String>{
        'AT',
        'BE',
        'BG',
        'HR',
        'CY',
        'CZ',
        'DK',
        'EE',
        'FI',
        'FR',
        'DE',
        'GR',
        'HU',
        'IE',
        'IT',
        'LV',
        'LT',
        'LU',
        'MT',
        'NL',
        'PL',
        'PT',
        'RO',
        'SK',
        'SI',
        'ES',
        'SE',
      };
      expect(kTelemetryOptInCountries, containsAll(eu27));
      expect(kTelemetryOptInCountries, containsAll(<String>['IS', 'LI', 'NO']));
      expect(kTelemetryOptInCountries, containsAll(<String>['GB', 'CH', 'KR']));

      // Spot-check the boundary: neighbours of the set that are not in it.
      for (final outside in <String>[
        'US',
        'CA',
        'JP',
        'AU',
        'TR',
        'UA',
        'CN',
        'TW',
      ]) {
        expect(
          kTelemetryOptInCountries,
          isNot(contains(outside)),
          reason: '$outside is not an opt-in region',
        );
      }
    });

    test('is stored upper-case, because the lookup upper-cases', () {
      for (final country in kTelemetryOptInCountries) {
        expect(country, equals(country.toUpperCase()));
      }
    });
  });

  group('the opt-in time zone set', () {
    test('lists no Europe/ zone, because the prefix already covers those', () {
      for (final zone in kTelemetryOptInTimeZones) {
        expect(
          zone.startsWith(kTelemetryOptInTimeZonePrefix),
          isFalse,
          reason: '$zone is redundant with the prefix',
        );
      }
    });

    test('is IANA-shaped, area/location', () {
      for (final zone in kTelemetryOptInTimeZones) {
        expect(zone, matches(RegExp(r'^[A-Z][A-Za-z]+/[A-Z][A-Za-z_]+$')));
      }
    });
  });

  group('telemetryTimeZoneRequiresOptIn', () {
    test('any Europe/ zone counts', () {
      for (final zone in <String>[
        'Europe/Berlin',
        'Europe/London',
        'Europe/Zurich',
        'Europe/Dublin',
        'Europe/Lisbon',
        'Europe/Oslo',
      ]) {
        expect(telemetryTimeZoneRequiresOptIn(zone), isTrue, reason: zone);
      }
    });

    test('over-inclusion under Europe/ is the documented trade', () {
      // Not opt-in regions, and deliberately caught anyway — a false positive
      // costs one measured installation, a false negative is collection
      // without consent.
      expect(telemetryTimeZoneRequiresOptIn('Europe/Moscow'), isTrue);
      expect(telemetryTimeZoneRequiresOptIn('Europe/Istanbul'), isTrue);
    });

    test('opt-in territory filed outside Europe/ counts', () {
      for (final zone in <String>[
        'Atlantic/Reykjavik',
        'Atlantic/Canary',
        'Asia/Nicosia',
        'Indian/Reunion',
        'Asia/Seoul',
      ]) {
        expect(telemetryTimeZoneRequiresOptIn(zone), isTrue, reason: zone);
      }
    });

    test('the rest of the world is left on', () {
      for (final zone in <String>[
        'America/Denver',
        'America/Toronto',
        'Asia/Tokyo',
        'Asia/Shanghai',
        'Australia/Sydney',
        'UTC',
      ]) {
        expect(telemetryTimeZoneRequiresOptIn(zone), isFalse, reason: zone);
      }
    });

    test('no zone is no evidence', () {
      expect(telemetryTimeZoneRequiresOptIn(null), isFalse);
      expect(telemetryTimeZoneRequiresOptIn(''), isFalse);
    });

    test('the match is exact', () {
      // Browsers report canonical IANA names; nothing here normalises.
      expect(telemetryTimeZoneRequiresOptIn('europe/berlin'), isFalse);
      expect(telemetryTimeZoneRequiresOptIn('Europe'), isFalse);
      expect(telemetryTimeZoneRequiresOptIn('asia/seoul'), isFalse);
    });
  });

  group('telemetryRequiresOptIn', () {
    test('an opt-in country anywhere in the list is enough', () {
      expect(telemetryRequiresOptIn(const [Locale('de', 'DE')]), isTrue);
      expect(telemetryRequiresOptIn(const [Locale('en', 'GB')]), isTrue);
      expect(telemetryRequiresOptIn(const [Locale('de', 'CH')]), isTrue);
      expect(telemetryRequiresOptIn(const [Locale('ko', 'KR')]), isTrue);

      // The case the "whole list, not just the first" rule exists for: an
      // English-first user whose machine is configured for Germany.
      expect(
        telemetryRequiresOptIn(const [Locale('en', 'US'), Locale('de', 'DE')]),
        isTrue,
      );
    });

    test('a non-opt-in country is left on', () {
      expect(telemetryRequiresOptIn(const [Locale('en', 'US')]), isFalse);
      expect(telemetryRequiresOptIn(const [Locale('en', 'CA')]), isFalse);
      expect(telemetryRequiresOptIn(const [Locale('ja', 'JP')]), isFalse);
    });

    test('a bare language tag is not evidence, and stays on', () {
      // The documented residual gap on platforms with no time zone signal.
      // Asserted so that changing it is a decision somebody makes on purpose
      // rather than a regression.
      expect(telemetryRequiresOptIn(const [Locale('en')]), isFalse);
      expect(telemetryRequiresOptIn(const [Locale('de')]), isFalse);
      expect(telemetryRequiresOptIn(const <Locale>[]), isFalse);
    });

    test('the time zone places a country-less locale', () {
      // The web case the second signal exists for: Firefox in Munich reports
      // `de`, Chrome in Dublin may report `en`, and neither carries a country.
      expect(
        telemetryRequiresOptIn(const [Locale('de')], timeZone: 'Europe/Berlin'),
        isTrue,
      );
      expect(
        telemetryRequiresOptIn(const [Locale('en')], timeZone: 'Europe/Dublin'),
        isTrue,
      );
      expect(
        telemetryRequiresOptIn(const <Locale>[], timeZone: 'Asia/Seoul'),
        isTrue,
      );
      // And the same locale with a zone that says otherwise stays on.
      expect(
        telemetryRequiresOptIn(const [
          Locale('de'),
        ], timeZone: 'America/Denver'),
        isFalse,
      );
    });

    test('either signal is enough; neither can veto the other', () {
      // A German-configured laptop travelling in Denver.
      expect(
        telemetryRequiresOptIn(
          const [Locale('de', 'DE')],
          timeZone: 'America/Denver',
        ),
        isTrue,
      );
      // An en-US machine in a Paris office.
      expect(
        telemetryRequiresOptIn(
          const [Locale('en', 'US')],
          timeZone: 'Europe/Paris',
        ),
        isTrue,
      );
      // Neither signal.
      expect(
        telemetryRequiresOptIn(
          const [Locale('en', 'US')],
          timeZone: 'America/Denver',
        ),
        isFalse,
      );
    });

    test('country case does not decide the outcome', () {
      // Locale normally upper-cases the subtag, but it does not enforce it and
      // a platform channel can hand over anything.
      expect(telemetryRequiresOptIn(const [Locale('de', 'de')]), isTrue);
    });

    test('language alone never triggers it — the country decides', () {
      // German is spoken in Germany, Austria and Switzerland, all opt-in, and
      // it is the obvious wrong signal to reach for. A German speaker in the
      // United States is not in an opt-in region.
      expect(telemetryRequiresOptIn(const [Locale('de', 'US')]), isFalse);
      // And the converse: an opt-in country with a non-European language.
      expect(telemetryRequiresOptIn(const [Locale('ja', 'DE')]), isTrue);
    });
  });

  group('telemetryDefaultConsentFor', () {
    test('is the inverse of the opt-in question', () {
      expect(telemetryDefaultConsentFor(const [Locale('de', 'DE')]), isFalse);
      expect(telemetryDefaultConsentFor(const [Locale('en', 'US')]), isTrue);
      expect(
        telemetryDefaultConsentFor(const [
          Locale('en'),
        ], timeZone: 'Europe/Rome'),
        isFalse,
      );
      expect(
        telemetryDefaultConsentFor(const [
          Locale('en'),
        ], timeZone: 'Asia/Tokyo'),
        isTrue,
      );
    });
  });
}
