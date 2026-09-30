// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared licence panel.
///
/// The properties worth guarding are the ones a well-meaning refactor would
/// break: that the panel renders with no licence at all, that it is not gated
/// on having one, and that every rejection reaches the user as a sentence
/// rather than an enum name or a stack trace.
void main() {
  const strings = CruxLicensePanelStringsEn();

  // The panel is a long scrolling settings pane. The default 800x600 test
  // surface puts its lower controls outside the window, where a tap silently
  // misses — so give it a desktop-sized viewport, which is where it runs.
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

  /// The panel renders dates in the viewer's own timezone, so the expected
  /// text has to be derived the same way rather than hard-coded.
  String localDate(DateTime utc) {
    final at = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Widget host({
    CruxLicenseStatus status = CruxLicenseStatus.openCore,
    CruxLicenseActions actions = const UnsupportedLicenseActions(),
    Future<String?> Function(BuildContext)? onPickCredentialFile,
  }) => ProviderScope(
    overrides: [
      licenseStatusProvider.overrideWithValue(status),
      licenseActionsProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CruxLicensePanel(
            product: CruxProduct.waveCrux,
            onPickCredentialFile: onPickCredentialFile,
          ),
        ),
      ),
    ),
  );

  group('with no licence', () {
    testWidgets('renders as a complete panel, not an error', (tester) async {
      await tester.pumpWidget(host());

      expect(find.text(strings.licenseTierOpenCore), findsOneWidget);
      expect(find.text(strings.licenseStateOpenCoreBody), findsOneWidget);
      expect(find.text(strings.licenseActivateButton), findsOneWidget);
    });

    testWidgets('is never hidden by tier — that would be a deadlock', (
      tester,
    ) async {
      // The whole point of the panel is entering a first key, so an Open Core
      // user must be able to reach every control that leads to one.
      await tester.pumpWidget(host());
      expect(find.byType(TextField), findsWidgets);
      expect(find.text(strings.licenseActivateButton), findsOneWidget);
    });

    testWidgets('hides this-machine controls until a licence exists', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      expect(find.text(strings.licenseMachineSectionTitle), findsNothing);
      expect(find.text(strings.licenseDeactivateButton), findsNothing);
    });
  });

  group('with a licence', () {
    final grant = LicenseGrant(
      issuerId: 'keygen',
      tier: LicenseTier.pro,
      products: const <CruxProduct>{CruxProduct.waveCrux},
      licenseId: 'lic-1',
      skuLookupKey: 'wavecrux-pro-monthly',
      email: 'buyer@example.com',
      expiry: DateTime.utc(2027, 3, 4),
    );

    testWidgets('shows tier, expiry and the facts support asks for', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: grant,
            seatsUsed: 2,
            seatsTotal: 3,
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseTierPro), findsOneWidget);
      expect(
        find.textContaining(localDate(DateTime.utc(2027, 3, 4))),
        findsOneWidget,
      );
      expect(find.text('wavecrux-pro-monthly'), findsOneWidget);
      expect(find.text('lic-1'), findsOneWidget);
      expect(find.text(strings.licenseSeatsInUse(2, 3)), findsOneWidget);
    });

    testWidgets('offers deactivation, behind a confirmation', (tester) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: grant,
          ),
          actions: actions,
        ),
      );

      await tapVisible(tester, find.text(strings.licenseDeactivateButton));
      expect(find.text(strings.licenseDeactivateConfirmTitle), findsOneWidget);

      await tapVisible(tester, find.text(strings.licenseCancelAction));
      expect(
        actions.deactivated,
        0,
        reason: 'cancelling a destructive confirm must do nothing',
      );

      await tapVisible(tester, find.text(strings.licenseDeactivateButton));
      await tapVisible(
        tester,
        find.text(strings.licenseDeactivateConfirmAction),
      );
      expect(actions.deactivated, 1);
    });

    testWidgets('grace shows days remaining and keeps the tier', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.grace,
            grant: grant,
            graceEndsAt: DateTime.now().add(
              const Duration(days: 12, hours: 1),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseTierPro), findsOneWidget);
      expect(find.text(strings.licenseStateGrace(12)), findsOneWidget);
    });

    testWidgets('an EDU licence shows the edition badge', (tester) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.edu,
              products: CruxProduct.values.toSet(),
              expiry: DateTime.utc(2027, 3, 4),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.byType(EditionBadge), findsOneWidget);
      expect(find.text(strings.licenseTierEdu), findsOneWidget);
    });
  });

  group('activation', () {
    testWidgets('an empty field is refused before any work happens', (
      tester,
    ) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(host(actions: actions));

      await tapVisible(tester, find.text(strings.licenseActivateButton));

      expect(actions.activatedWith, isEmpty);
      expect(find.text(strings.licenseErrorMalformed), findsOneWidget);
    });

    testWidgets('a pasted credential reaches the service verbatim', (
      tester,
    ) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(host(actions: actions));

      await tester.enterText(find.byType(TextField).first, '  key/abc.def  ');
      await tapVisible(tester, find.text(strings.licenseActivateButton));

      expect(actions.activatedWith, <String>['key/abc.def']);
    });

    testWidgets('a successful activation clears the field', (tester) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(host(actions: actions));

      await tester.enterText(find.byType(TextField).first, 'key/abc.def');
      await tapVisible(tester, find.text(strings.licenseActivateButton));

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        isEmpty,
      );
      expect(find.text(strings.licenseActivatedMessage), findsOneWidget);
    });

    testWidgets('every rejection reaches the user as a sentence', (
      tester,
    ) async {
      // No enum name, no exception text. The mapping is exhaustive by the
      // switch in the panel; this proves each arm produces the right string.
      const expected = <LicenseRejection, String>{
        LicenseRejection.malformed: 'That does not look like a license key',
        LicenseRejection.undecodablePayload:
            'That does not look like a license key',
        LicenseRejection.unsupportedAlgorithm: 'license file is encrypted',
        LicenseRejection.untrustedIssuer: 'could not be verified',
        LicenseRejection.wrongAccount: 'not issued for this product family',
        LicenseRejection.unknownPolicy: 'newer than this version',
        LicenseRejection.productNotEntitled: 'different product in the suite',
        LicenseRejection.wrongMachine: 'different machine',
      };
      expect(
        expected.keys.toSet(),
        LicenseRejection.values.toSet(),
        reason: 'a new rejection needs a sentence, not a default',
      );

      for (final entry in expected.entries) {
        final actions = _RecordingActions(
          result: LicenseActionFailed(
            CruxLicenseActionFailure.rejected,
            rejection: entry.key,
          ),
        );
        await tester.pumpWidget(host(actions: actions));
        await tester.enterText(find.byType(TextField).first, 'key/abc.def');
        await tapVisible(tester, find.text(strings.licenseActivateButton));

        expect(
          find.textContaining(entry.value),
          findsOneWidget,
          reason: entry.key.name,
        );
      }
    });

    testWidgets('being offline says the licence keeps working', (
      tester,
    ) async {
      final actions = _RecordingActions(
        result: const LicenseActionFailed(CruxLicenseActionFailure.offline),
      );
      await tester.pumpWidget(host(actions: actions));
      await tester.enterText(find.byType(TextField).first, 'key/abc.def');
      await tapVisible(tester, find.text(strings.licenseActivateButton));

      expect(find.textContaining('keeps working'), findsOneWidget);
    });
  });

  group('capabilities', () {
    testWidgets('unsupported actions hide their sections entirely', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      expect(find.text(strings.licenseOfflineSectionTitle), findsNothing);
      expect(find.text(strings.licenseBuyButton), findsNothing);
    });

    testWidgets('supported actions render their sections', (tester) async {
      await tester.pumpWidget(host(actions: _RecordingActions()));
      expect(find.text(strings.licenseOfflineSectionTitle), findsOneWidget);
      expect(find.text(strings.licenseBuyButton), findsOneWidget);
    });

    testWidgets('Manage subscription is hidden with nowhere to send the user', (
      tester,
    ) async {
      // A "Manage subscription" link that 404s is worse than no link: the
      // user concludes their purchase is broken. The destination needs an
      // account page and a Stripe portal link that arrive later than the
      // pricing page, so the two capabilities are separate.
      final grant = LicenseGrant(
        issuerId: 'keygen',
        tier: LicenseTier.pro,
        products: const <CruxProduct>{CruxProduct.waveCrux},
        expiry: DateTime.utc(2027),
      );
      final status = CruxLicenseStatus(
        activation: CruxLicenseActivation.active,
        grant: grant,
      );

      await tester.pumpWidget(
        host(status: status, actions: _RecordingActions(manageLink: false)),
      );
      expect(find.text(strings.licenseManageButton), findsNothing);
      expect(find.text(strings.licenseBuyButton), findsOneWidget);

      await tester.pumpWidget(
        host(status: status, actions: _RecordingActions()),
      );
      expect(find.text(strings.licenseManageButton), findsOneWidget);
    });

    testWidgets('the file button appears only when a picker is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(host(actions: _RecordingActions()));
      expect(find.text(strings.licenseChooseFileButton), findsNothing);

      await tester.pumpWidget(
        host(
          actions: _RecordingActions(),
          onPickCredentialFile: (_) async => 'key/from.file',
        ),
      );
      expect(find.text(strings.licenseChooseFileButton), findsOneWidget);

      await tapVisible(tester, find.text(strings.licenseChooseFileButton));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'key/from.file',
      );
    });
  });

  group('the key field explains itself differently once licensed', () {
    // The field stays available on purpose: a licence is replaced more often
    // than it is first entered — EDU to Pro, Pro to Enterprise, a renewed
    // key, a personal key swapped for a company one. Hiding it would strand
    // all of those. What it must not do is keep reading like first-run text.
    testWidgets('first run invites a first key', (tester) async {
      await tester.pumpWidget(host(actions: _RecordingActions()));
      expect(find.text(strings.licenseKeyFieldHelper), findsOneWidget);
      expect(find.text(strings.licenseKeyFieldHelperActive), findsNothing);
    });

    testWidgets('once licensed it explains replacement', (tester) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.edu,
              products: CruxProduct.values.toSet(),
              expiry: DateTime.utc(2027, 8, 21),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseKeyFieldHelperActive), findsOneWidget);
      expect(find.text(strings.licenseKeyFieldHelper), findsNothing);
      expect(
        find.text(strings.licenseActivateButton),
        findsOneWidget,
        reason: 'an upgrade path must stay reachable',
      );
    });
  });

  group('the educational licence', () {
    testWidgets('is offered only while the user has none', (tester) async {
      // Offering it to somebody who already holds a licence invites them to
      // end up with two.
      await tester.pumpWidget(host(actions: _RecordingActions()));
      expect(find.text(strings.licenseEduSectionTitle), findsOneWidget);

      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.pro,
              products: const <CruxProduct>{CruxProduct.waveCrux},
              expiry: DateTime.utc(2027),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );
      expect(find.text(strings.licenseEduSectionTitle), findsNothing);
    });

    testWidgets('says the licence arrives by email, not here', (tester) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(host(actions: actions));

      await tester.enterText(
        find.byType(TextField).last,
        'student@university.edu',
      );
      await tapVisible(tester, find.text(strings.licenseEduRequestButton));

      expect(actions.eduRequests, <String>['student@university.edu']);
      expect(find.text(strings.licenseEduCheckYourEmail), findsOneWidget);
    });

    testWidgets('a reviewed address is not told to follow a link', (
      tester,
    ) async {
      // Measured against the live backend: an address whose domain is not
      // allow-listed gets a person and no confirmation mail at all. The panel
      // showed "we have sent a link to confirm the address" anyway, so the
      // applicant most likely to need clear instructions — the one whose
      // institution we have never heard of — was the one told to wait for
      // mail that was never sent.
      final actions = _RecordingActions(
        result: const LicenseActionSucceeded(underReview: true),
      );
      await tester.pumpWidget(host(actions: actions));

      await tester.enterText(
        find.byType(TextField).last,
        'someone@robotics-lab.example',
      );
      await tapVisible(tester, find.text(strings.licenseEduRequestButton));

      expect(find.text(strings.licenseEduUnderReview), findsOneWidget);
      expect(find.text(strings.licenseEduCheckYourEmail), findsNothing);
    });

    testWidgets('a refused address is explained in the field', (tester) async {
      final actions = _RecordingActions(
        result: const LicenseActionFailed(
          CruxLicenseActionFailure.invalidEmail,
        ),
      );
      await tester.pumpWidget(host(actions: actions));

      await tester.enterText(find.byType(TextField).last, 'me@example.com');
      await tapVisible(tester, find.text(strings.licenseEduRequestButton));

      expect(find.text(strings.licenseErrorInvalidEmail), findsOneWidget);
      expect(find.text(strings.licenseEduCheckYourEmail), findsNothing);
    });
  });

  group('the offline section', () {
    final licensed = CruxLicenseStatus(
      activation: CruxLicenseActivation.active,
      grant: LicenseGrant(
        issuerId: 'keygen',
        tier: LicenseTier.enterprise,
        products: CruxProduct.values.toSet(),
        licenseId: 'lic-9',
        expiry: DateTime.utc(2027),
      ),
      seatsUsed: 3,
      seatsTotal: 25,
      machineLabel: 'lab-01',
      lastCheckedAt: DateTime.utc(2026, 9, 1, 14, 30),
    );

    testWidgets('exporting shows the request so it can be copied', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(status: licensed, actions: _RecordingActions()),
      );

      await tapVisible(tester, find.text(strings.licenseExportRequestButton));
      expect(find.text(strings.licenseExportRequestTitle), findsOneWidget);
      expect(find.text('request-blob'), findsOneWidget);

      // Intercept the clipboard so the copy is deterministic and the payload
      // is checkable — the point of the button is what lands on the clipboard,
      // not that it was pressed.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tapVisible(tester, find.text(strings.licenseCopyAction));
      expect(find.text(strings.licenseExportRequestTitle), findsNothing);
      await tester.pumpAndSettle();

      expect(copied, 'request-blob');
      expect(
        find.text(strings.licenseCopiedMessage),
        findsOneWidget,
        reason: 'a copy button with no feedback gets pressed twice',
      );
    });

    testWidgets('the export dialog closes without copying', (tester) async {
      await tester.pumpWidget(
        host(status: licensed, actions: _RecordingActions()),
      );
      await tapVisible(tester, find.text(strings.licenseExportRequestButton));
      await tapVisible(tester, find.text(strings.licenseCloseAction));
      expect(find.text(strings.licenseExportRequestTitle), findsNothing);
    });

    testWidgets('importing an empty field is refused', (tester) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(host(status: licensed, actions: actions));

      await tapVisible(tester, find.text(strings.licenseImportTokenButton));
      expect(find.text(strings.licenseErrorMalformed), findsOneWidget);
    });

    testWidgets('importing a pasted token goes through activation', (
      tester,
    ) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(host(status: licensed, actions: actions));

      await tester.enterText(find.byType(TextField).first, 'a-licence-file');
      await tapVisible(tester, find.text(strings.licenseImportTokenButton));

      expect(find.text(strings.licenseActivatedMessage), findsOneWidget);
    });
  });

  group('the machine section', () {
    testWidgets('names the machine, the seats and the last check', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.enterprise,
              products: CruxProduct.values.toSet(),
              email: 'team@example.com',
              expiry: DateTime.utc(2027),
            ),
            seatsUsed: 3,
            seatsTotal: 25,
            machineLabel: 'lab-01',
            lastCheckedAt: DateTime.utc(2026, 9, 1, 14, 30),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text('lab-01'), findsOneWidget);
      expect(find.text(strings.licenseSeatsInUse(3, 25)), findsOneWidget);
      expect(find.text('team@example.com'), findsOneWidget);
      expect(find.textContaining('2026-09-01'), findsOneWidget);
      expect(find.text(strings.licenseTierEnterprise), findsOneWidget);
    });

    testWidgets('never having checked online is stated, not hidden', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.pro,
              products: const <CruxProduct>{CruxProduct.waveCrux},
              expiry: DateTime.utc(2027),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseNeverChecked), findsOneWidget);
    });

    testWidgets('Check now reaches the service', (tester) async {
      final actions = _RecordingActions();
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.pro,
              products: const <CruxProduct>{CruxProduct.waveCrux},
              expiry: DateTime.utc(2027),
            ),
          ),
          actions: actions,
        ),
      );

      await tapVisible(tester, find.text(strings.licenseRefreshButton));
      expect(actions.refreshed, 1);
    });

    testWidgets('a stored credential that no longer validates says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: const CruxLicenseStatus(
            activation: CruxLicenseActivation.invalid,
            rejection: LicenseRejection.unknownPolicy,
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseStateInvalid), findsOneWidget);
      expect(
        find.textContaining('newer than this version'),
        findsOneWidget,
        reason: 'the reason is shown, not just the fact',
      );
    });

    testWidgets('an expired licence falls back to Open Core wording', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.expired,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.pro,
              products: const <CruxProduct>{CruxProduct.waveCrux},
              expiry: DateTime.utc(2026),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseStateExpired), findsOneWidget);
      expect(find.text(strings.licenseTierOpenCore), findsOneWidget);
    });

    testWidgets('a perpetual licence says so rather than showing no date', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: const CruxLicenseStatus(
            activation: CruxLicenseActivation.active,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.pro,
              products: <CruxProduct>{CruxProduct.waveCrux},
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseStatePerpetual), findsOneWidget);
    });

    testWidgets('a valid key not yet registered says exactly that', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status: CruxLicenseStatus(
            activation: CruxLicenseActivation.notActivatedOnThisMachine,
            grant: LicenseGrant(
              issuerId: 'keygen',
              tier: LicenseTier.pro,
              products: const <CruxProduct>{CruxProduct.waveCrux},
              expiry: DateTime.utc(2027),
            ),
          ),
          actions: _RecordingActions(),
        ),
      );

      expect(find.text(strings.licenseStateNotActivated), findsOneWidget);
      expect(find.text(strings.licenseTierPro), findsOneWidget);
    });
  });

  group('the settings category', () {
    test('carries the stable id and is not tier-aware', () {
      final category = cruxLicenseSettingsCategory(
        product: CruxProduct.netCrux,
        strings: (_) => strings,
      );
      expect(category.id, kCruxLicenseCategoryId);
      expect(category.id, 'pro.license');
      expect(category.icon, kCruxLicenseCategoryIcon);
    });

    testWidgets('builds the panel at Open Core', (tester) async {
      final category = cruxLicenseSettingsCategory(
        product: CruxProduct.simCrux,
        strings: (_) => strings,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Builder(builder: category.bodyBuilder),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CruxLicensePanel), findsOneWidget);
      expect(find.text(strings.licenseTierOpenCore), findsOneWidget);
    });
  });
}

/// Records what the panel asked for, and answers with a fixed result.
class _RecordingActions implements CruxLicenseActions {
  _RecordingActions({
    this.result = const LicenseActionSucceeded(),
    this.manageLink = true,
  });

  final bool manageLink;

  final CruxLicenseActionResult result;
  final List<String> activatedWith = <String>[];
  final List<String> eduRequests = <String>[];
  int deactivated = 0;
  int refreshed = 0;

  @override
  Future<CruxLicenseActionResult> activate(String credential) async {
    activatedWith.add(credential);
    return result;
  }

  @override
  Future<CruxLicenseActionResult> deactivateThisMachine() async {
    deactivated++;
    return result;
  }

  @override
  Future<CruxLicenseActionResult> refresh() async {
    refreshed++;
    return result;
  }

  @override
  Future<CruxLicenseActionResult> exportOfflineRequest() async =>
      const LicenseActionSucceeded(payload: 'request-blob');

  @override
  Future<CruxLicenseActionResult> importOfflineToken(String token) async =>
      result;

  @override
  Future<CruxLicenseActionResult> openPurchasePage() async => result;

  @override
  Future<CruxLicenseActionResult> openManagePage() async => result;

  @override
  bool get supportsDeactivation => true;

  @override
  bool get supportsOfflineActivation => true;

  @override
  Future<CruxLicenseActionResult> requestEducationalLicense(
    String email,
  ) async {
    eduRequests.add(email);
    return result;
  }

  @override
  bool get supportsPurchaseLinks => true;

  @override
  bool get supportsManageLink => manageLink;

  @override
  bool get supportsEducationalRequest => true;
}
