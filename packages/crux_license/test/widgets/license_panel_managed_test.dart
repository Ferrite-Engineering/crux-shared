// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A licence panel on a managed deployment: **locked, not hidden.**
///
/// Hiding it would be tidier and is wrong. Support needs the engineer on the
/// phone to read their own tier, expiry and seat state, and a hidden panel
/// turns every licence question into a blind ticket.
void main() {
  const strings = CruxLicensePanelStringsEn();

  CruxLicenseStatus statusFor(
    CruxLicenseActivation activation, {
    DateTime? graceEndsAt,
  }) => CruxLicenseStatus(
    activation: activation,
    grant: const LicenseGrant(
      issuerId: 'keygen',
      tier: LicenseTier.enterprise,
      products: {CruxProduct.waveCrux},
    ),
    graceEndsAt: graceEndsAt,
    machineLabel: 'lab-01',
  );

  Future<void> pump(
    WidgetTester tester, {
    required bool managed,
    CruxLicenseActivation activation = CruxLicenseActivation.active,
    DateTime? graceEndsAt,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        licenseManagedByOrganizationProvider.overrideWithValue(managed),
        licenseStatusProvider.overrideWithValue(
          statusFor(activation, graceEndsAt: graceEndsAt),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CruxLicensePanel(
              product: CruxProduct.waveCrux,
            ),
          ),
        ),
      ),
    ),
  );

  group('a managed installation', () {
    testWidgets('says the organization licensed it', (tester) async {
      await pump(tester, managed: true);
      expect(find.text(strings.licenseManagedByOrganization), findsOneWidget);
    });

    testWidgets('offers no key entry', (tester) async {
      await pump(tester, managed: true);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(strings.licenseKeySectionTitle), findsNothing);
    });

    testWidgets("offers no deactivation — the seat is the org's", (
      tester,
    ) async {
      // Releasing the seat of a machine the organization licensed would leave
      // it unlicensed with no way to fix it from here.
      await pump(tester, managed: true);
      expect(find.text(strings.licenseDeactivateButton), findsNothing);
    });

    testWidgets('KEEPS the status readable — that is the whole point', (
      tester,
    ) async {
      await pump(tester, managed: true);
      expect(
        find.text(strings.licenseMachineSectionTitle),
        findsOneWidget,
        reason: 'support asks the engineer to read this back',
      );
      expect(find.text('lab-01'), findsOneWidget);
      // Refresh stays: it is read-only and it is what support asks for.
      expect(find.text(strings.licenseRefreshButton), findsOneWidget);
    });

    testWidgets('an expired policy licence names the grace window and points '
        'at the administrator', (tester) async {
      // The state nobody will have looked at before a customer finds it.
      await pump(
        tester,
        managed: true,
        activation: CruxLicenseActivation.grace,
        graceEndsAt: DateTime.utc(2027, 3),
      );
      expect(find.text(strings.licenseManagedExpired), findsOneWidget);
      // It must NOT tell them to do something they cannot do.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('an active licence shows no expiry warning', (tester) async {
      await pump(tester, managed: true);
      expect(find.text(strings.licenseManagedExpired), findsNothing);
    });
  });

  group('an unmanaged installation is unchanged', () {
    testWidgets('still offers key entry', (tester) async {
      await pump(tester, managed: false);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text(strings.licenseManagedByOrganization), findsNothing);
    });
  });
}
