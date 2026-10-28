// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the main window says about a licence's term, as a pure function of
/// the status and the clock.
void main() {
  final expiry = DateTime.utc(2027);

  CruxLicenseStatus statusOf(
    CruxLicenseActivation activation, {
    bool evaluation = false,
    DateTime? graceEndsAt,
    bool clockSetBack = false,
    DateTime? expiresAt,
    bool noExpiry = false,
  }) => CruxLicenseStatus(
    activation: activation,
    grant: LicenseGrant(
      issuerId: 'keygen',
      tier: LicenseTier.enterprise,
      products: const {CruxProduct.waveCrux},
      licenseId: 'lic-1',
      expiry: noExpiry ? null : (expiresAt ?? expiry),
      isEvaluation: evaluation,
    ),
    graceEndsAt: graceEndsAt,
    clockSetBack: clockSetBack,
  );

  test('the lead times default to 30 days, and 14 for an evaluation', () {
    expect(kLicenseExpiryWarningDays, 30);
    expect(kEvaluationExpiryWarningDays, 14);
  });

  group('before expiry', () {
    test('nothing outside the window', () {
      final now = expiry.subtract(const Duration(days: 31));
      expect(
        cruxLicenseExpiryNoticeFor(
          statusOf(CruxLicenseActivation.active),
          now: now,
        ),
        isNull,
      );
    });

    test('a notice from exactly 30 days before', () {
      final now = expiry.subtract(const Duration(days: 30));
      final notice = cruxLicenseExpiryNoticeFor(
        statusOf(CruxLicenseActivation.active),
        now: now,
      );
      expect(notice!.kind, CruxLicenseNoticeKind.expiringSoon);
      expect(notice.tier, LicenseTier.enterprise);
      expect(notice.expiry, expiry);
    });

    test('a machine not yet registered is warned too', () {
      final notice = cruxLicenseExpiryNoticeFor(
        statusOf(CruxLicenseActivation.notActivatedOnThisMachine),
        now: expiry.subtract(const Duration(days: 3)),
      );
      expect(notice!.kind, CruxLicenseNoticeKind.expiringSoon);
    });

    test('an evaluation counts down from 14 days, not 30', () {
      final status = statusOf(CruxLicenseActivation.active, evaluation: true);
      expect(
        cruxLicenseExpiryNoticeFor(
          status,
          now: expiry.subtract(const Duration(days: 15)),
        ),
        isNull,
      );
      final notice = cruxLicenseExpiryNoticeFor(
        status,
        now: expiry.subtract(const Duration(days: 14)),
      );
      expect(notice!.kind, CruxLicenseNoticeKind.expiringSoon);
      expect(notice.evaluation, isTrue);
    });

    test("the windows are the caller's to move", () {
      final now = expiry.subtract(const Duration(days: 40));
      expect(
        cruxLicenseExpiryNoticeFor(
          statusOf(CruxLicenseActivation.active),
          now: now,
          warningDays: 45,
        ),
        isNotNull,
      );
    });
  });

  test('grace counts the days the panel counts', () {
    final now = expiry.add(const Duration(days: 3));
    final status = statusOf(
      CruxLicenseActivation.grace,
      graceEndsAt: expiry.add(const Duration(days: 90)),
    );
    final notice = cruxLicenseExpiryNoticeFor(status, now: now);
    expect(notice!.kind, CruxLicenseNoticeKind.inGrace);
    expect(notice.graceDaysRemaining, status.graceDaysRemainingAt(now));
    expect(notice.graceDaysRemaining, 87);
  });

  test('after grace, the drop to Open Core', () {
    final notice = cruxLicenseExpiryNoticeFor(
      statusOf(CruxLicenseActivation.expired),
      now: expiry.add(const Duration(days: 91)),
    );
    expect(notice!.kind, CruxLicenseNoticeKind.ended);
    expect(notice.tier, LicenseTier.enterprise);
  });

  test('a clock set back is an ended evaluation that says why', () {
    final notice = cruxLicenseExpiryNoticeFor(
      statusOf(
        CruxLicenseActivation.expired,
        evaluation: true,
        clockSetBack: true,
      ),
      now: DateTime.utc(2026, 9),
    );
    expect(notice!.kind, CruxLicenseNoticeKind.ended);
    expect(notice.clockSetBack, isTrue);
    expect(notice.identity, endsWith('|clock'));
  });

  group('nothing to say', () {
    test('at Open Core', () {
      expect(
        cruxLicenseExpiryNoticeFor(
          CruxLicenseStatus.openCore,
          now: DateTime.utc(2026, 12, 31),
        ),
        isNull,
      );
    });

    test('for a term licence with no expiry date', () {
      expect(
        cruxLicenseExpiryNoticeFor(
          statusOf(CruxLicenseActivation.active, noExpiry: true),
          now: DateTime.utc(2026, 12, 31),
        ),
        isNull,
      );
    });

    test('for the states the panel explains', () {
      for (final activation in [
        CruxLicenseActivation.invalid,
        CruxLicenseActivation.noSeat,
      ]) {
        expect(
          cruxLicenseExpiryNoticeFor(
            statusOf(activation),
            now: expiry.subtract(const Duration(days: 1)),
          ),
          isNull,
        );
      }
    });
  });

  test('the identity ignores the day count, so midnight is not a new '
      'notice', () {
    final status = statusOf(
      CruxLicenseActivation.grace,
      graceEndsAt: expiry.add(const Duration(days: 30)),
    );
    final a = cruxLicenseExpiryNoticeFor(
      status,
      now: expiry.add(const Duration(days: 1)),
    );
    final b = cruxLicenseExpiryNoticeFor(
      status,
      now: expiry.add(const Duration(days: 2)),
    );
    expect(a!.identity, b!.identity);
    expect(a, isNot(b));
  });
}
