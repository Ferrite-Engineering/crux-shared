// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBetaExpiryDate', () {
    test('parses a valid yyyymmdd into a local midnight DateTime', () {
      final parsed = parseBetaExpiryDate(20260915);

      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 9);
      expect(parsed.day, 15);
      expect(parsed.hour, 0);
      expect(parsed.minute, 0);
      expect(parsed.second, 0);
    });

    test('parses single-digit month and day correctly', () {
      final parsed = parseBetaExpiryDate(20260105);

      expect(parsed, isNotNull);
      expect(parsed!.month, 1);
      expect(parsed.day, 5);
    });

    test('returns null for 0 (the absent-define sentinel)', () {
      expect(parseBetaExpiryDate(0), isNull);
    });

    test('returns null for a negative value', () {
      expect(parseBetaExpiryDate(-20260915), isNull);
    });

    test('returns null for an out-of-range month', () {
      expect(parseBetaExpiryDate(20261315), isNull);
    });

    test('returns null for an out-of-range day', () {
      expect(parseBetaExpiryDate(20260932), isNull);
    });

    test('returns null for a non-existent calendar date (Feb 30)', () {
      expect(parseBetaExpiryDate(20260230), isNull);
    });

    test('returns null for an implausibly small year', () {
      expect(parseBetaExpiryDate(19990915), isNull);
    });
  });

  group('daysUntilBetaExpiry', () {
    final expiry = DateTime(2026, 9, 15);

    test('returns null when no expiry applies', () {
      expect(daysUntilBetaExpiry(DateTime(2026, 8, 2)), isNull);
    });

    test('counts whole days regardless of time-of-day', () {
      expect(
        daysUntilBetaExpiry(DateTime(2026, 9, 8, 23, 59), expiry: expiry),
        7,
      );
      expect(
        daysUntilBetaExpiry(DateTime(2026, 9, 8, 1), expiry: expiry),
        7,
      );
    });

    test('is 0 on the expiry date itself', () {
      expect(
        daysUntilBetaExpiry(DateTime(2026, 9, 15, 12), expiry: expiry),
        0,
      );
    });

    test('is negative past the expiry date', () {
      expect(
        daysUntilBetaExpiry(DateTime(2026, 9, 17), expiry: expiry),
        -2,
      );
    });
  });

  group('betaExpiryStatusFor', () {
    final expiry = DateTime(2026, 9, 15);

    test('notApplicable when no expiry is set', () {
      expect(
        betaExpiryStatusFor(DateTime(2026, 6, 11)),
        BetaExpiryStatus.notApplicable,
      );
    });

    test('active well before the warning window', () {
      // ~44 days out with the default 7-day window.
      expect(
        betaExpiryStatusFor(DateTime(2026, 8, 2), expiry: expiry),
        BetaExpiryStatus.active,
      );
    });

    test('active on the day just outside the warning window', () {
      // 8 days out with a 7-day window is still active.
      expect(
        betaExpiryStatusFor(DateTime(2026, 9, 7), expiry: expiry),
        BetaExpiryStatus.active,
      );
    });

    test('expiringSoon on the first day inside the warning window', () {
      // Exactly 7 days out with a 7-day window.
      expect(
        betaExpiryStatusFor(DateTime(2026, 9, 8), expiry: expiry),
        BetaExpiryStatus.expiringSoon,
      );
    });

    test('expiringSoon the day before expiry', () {
      expect(
        betaExpiryStatusFor(DateTime(2026, 9, 14, 23), expiry: expiry),
        BetaExpiryStatus.expiringSoon,
      );
    });

    test('expired on the exact expiry day', () {
      expect(
        betaExpiryStatusFor(DateTime(2026, 9, 15), expiry: expiry),
        BetaExpiryStatus.expired,
      );
    });

    test('expired the day after expiry', () {
      expect(
        betaExpiryStatusFor(DateTime(2026, 9, 16), expiry: expiry),
        BetaExpiryStatus.expired,
      );
    });

    test('honors a custom warning window', () {
      // 20 days out: active with a 7-day window, expiringSoon with a 30-day.
      expect(
        betaExpiryStatusFor(DateTime(2026, 8, 26), expiry: expiry),
        BetaExpiryStatus.active,
      );
      expect(
        betaExpiryStatusFor(
          DateTime(2026, 8, 26),
          expiry: expiry,
          warningDays: 30,
        ),
        BetaExpiryStatus.expiringSoon,
      );
    });
  });

  group('build-injected defaults (no --dart-define in the test runner)', () {
    test('kBetaExpiry is null — test builds never expire', () {
      expect(kBetaExpiry, isNull);
    });

    test('kBetaExpiryWarningDays defaults to 7', () {
      expect(kBetaExpiryWarningDays, 7);
    });

    test('default status is notApplicable when no expiry is injected', () {
      expect(
        betaExpiryStatusFor(DateTime(2026, 6, 11)),
        BetaExpiryStatus.notApplicable,
      );
    });
  });

  group('trustedBetaExpiryNow', () {
    test('no server time observed — returns the device clock unchanged', () {
      final deviceNow = DateTime(2026, 6, 11, 9);
      expect(trustedBetaExpiryNow(deviceNow), deviceNow);
    });

    test('device clock ahead of server time — device wins', () {
      // Normal case: time has passed since the last manifest fetch.
      final deviceNow = DateTime(2026, 6, 11, 12);
      final serverTime = DateTime(2026, 6, 11, 9);
      expect(
        trustedBetaExpiryNow(deviceNow, observedServerTime: serverTime),
        deviceNow,
      );
    });

    test('device clock set BACK behind server time — server time wins', () {
      final deviceNow = DateTime(2026, 6); // user rolled the clock back
      final serverTime = DateTime(2026, 6, 11);
      expect(
        trustedBetaExpiryNow(deviceNow, observedServerTime: serverTime),
        serverTime,
      );
    });

    test('equal clocks — returns that instant', () {
      final t = DateTime(2026, 6, 11, 10, 30);
      expect(trustedBetaExpiryNow(t, observedServerTime: t), t);
    });
  });

  group('clock-tampering hardening (server_time → betaExpiryStatusFor)', () {
    final expiry = DateTime(2026, 9);

    test('clock set BACK is still treated as expired via server time', () {
      // Device says it is well before expiry (not even in the warning window)…
      final deviceNow = DateTime(2026);
      expect(
        betaExpiryStatusFor(deviceNow, expiry: expiry),
        BetaExpiryStatus.active,
      );
      // …but the server has been seen past the expiry date, so the trusted
      // reckoning treats the build as expired.
      final serverTime = DateTime(2026, 9, 2);
      expect(
        betaExpiryStatusFor(
          trustedBetaExpiryNow(deviceNow, observedServerTime: serverTime),
          expiry: expiry,
        ),
        BetaExpiryStatus.expired,
      );
    });

    test('no server time yet — falls back to the device clock (unchanged)', () {
      final deviceNow = DateTime(2026);
      expect(
        betaExpiryStatusFor(trustedBetaExpiryNow(deviceNow), expiry: expiry),
        BetaExpiryStatus.active,
      );
    });

    test('server time present and consistent — same status as the device', () {
      final deviceNow = DateTime(2026, 8, 28); // inside the 7-day window
      final serverTime = DateTime(2026, 8, 28, 1);
      expect(
        betaExpiryStatusFor(deviceNow, expiry: expiry),
        BetaExpiryStatus.expiringSoon,
      );
      expect(
        betaExpiryStatusFor(
          trustedBetaExpiryNow(deviceNow, observedServerTime: serverTime),
          expiry: expiry,
        ),
        BetaExpiryStatus.expiringSoon,
      );
    });
  });
}
