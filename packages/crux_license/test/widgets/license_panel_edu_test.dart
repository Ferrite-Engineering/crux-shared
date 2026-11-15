// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The licence panel with a self-issued educational licence.
///
/// Such a licence is never presented to Keygen, so the controls that act on
/// a Keygen licence (releasing this machine's seat, the subscription page,
/// the check-in) have nothing to act on and are not offered. What the user
/// needs to read is: EDU, the address it was issued to, and when it ends.
void main() {
  const strings = CruxLicensePanelStringsEn();

  setUp(
    () =>
        TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .views
            .first
          ..physicalSize = const Size(1400, 2400)
          ..devicePixelRatio = 1.0,
  );

  tearDown(
    () =>
        TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .views
            .first
          ..resetPhysicalSize()
          ..resetDevicePixelRatio(),
  );

  String localDate(DateTime utc) {
    final at = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
  }

  Widget host(CruxLicenseStatus status) => ProviderScope(
    overrides: [
      licenseStatusProvider.overrideWithValue(status),
      licenseActionsProvider.overrideWithValue(const _AllActions()),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CruxLicensePanel(product: CruxProduct.waveCrux),
        ),
      ),
    ),
  );

  LicenseGrant grant(String issuerId) => LicenseGrant(
    issuerId: issuerId,
    tier: LicenseTier.edu,
    products: CruxProduct.values.toSet(),
    licenseId: 'edu-lic-1',
    email: 'student@example.edu',
    expiry: DateTime.utc(2027, 8, 2),
  );

  testWidgets('shows EDU, the address and the expiry', (tester) async {
    await tester.pumpWidget(
      host(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
          grant: grant(kEduLicenseIssuerId),
          machineLabel: 'lab-01',
        ),
      ),
    );

    expect(find.text(strings.licenseTierEdu), findsOneWidget);
    expect(find.text('student@example.edu'), findsOneWidget);
    expect(
      find.text(
        strings.licenseStateActive(localDate(DateTime.utc(2027, 8, 2))),
      ),
      findsOneWidget,
    );
  });

  testWidgets('offers no Keygen-only action', (tester) async {
    await tester.pumpWidget(
      host(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
          grant: grant(kEduLicenseIssuerId),
          machineLabel: 'lab-01',
        ),
      ),
    );

    expect(find.text(strings.licenseDeactivateButton), findsNothing);
    expect(find.text(strings.licenseManageButton), findsNothing);
    expect(find.text(strings.licenseRefreshButton), findsNothing);
    expect(find.text(strings.licenseMachineSectionTitle), findsNothing);
    expect(
      find.text(strings.licenseNeverChecked),
      findsNothing,
      reason: 'there is no issuer it could ever have been checked with',
    );
    // Entering a different licence, and buying one, still apply.
    expect(find.text(strings.licenseActivateButton), findsOneWidget);
    expect(find.text(strings.licenseBuyButton), findsOneWidget);
  });

  testWidgets('says where the licence is kept when it is in a file', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
          grant: grant(kEduLicenseIssuerId),
          credentialFile: '/home/student/.config/crux/wavecrux.license',
        ),
      ),
    );

    expect(
      find.text(
        strings.licenseStoredInFile(
          '/home/student/.config/crux/wavecrux.license',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(strings.licenseDeactivateButton), findsNothing);
    expect(find.text(strings.licenseRefreshButton), findsNothing);
  });

  testWidgets('a Keygen EDU licence keeps its machine controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
          grant: grant('keygen'),
          machineLabel: 'lab-01',
        ),
      ),
    );

    expect(find.text(strings.licenseDeactivateButton), findsOneWidget);
    expect(find.text(strings.licenseManageButton), findsOneWidget);
    expect(find.text(strings.licenseRefreshButton), findsOneWidget);
  });
}

/// Every action the panel can offer, offered.
class _AllActions extends UnsupportedLicenseActions {
  const _AllActions();

  @override
  bool get supportsDeactivation => true;

  @override
  bool get supportsManageLink => true;

  @override
  bool get supportsPurchaseLinks => true;

  @override
  bool get supportsOfflineActivation => true;

  @override
  bool get supportsEducationalRequest => true;
}
