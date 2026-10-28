// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The licence-expiry strip in the main window, one test per state the
// licence can be in, plus the properties a refactor would quietly break: it
// is announced once, it never takes focus, and the app under it keeps its
// state when the strip comes and goes.
//
// MUTATION: announcing from build() without the identity check turns
// "announced once" red; returning widget.child bare when nothing shows
// (instead of the stable Column) turns "the app keeps its state" red.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_license/src/license_panel_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _expiry = DateTime.utc(2027, 1, 1, 12);

String _date(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

CruxLicenseStatus _status(
  CruxLicenseActivation activation, {
  LicenseTier tier = LicenseTier.pro,
  bool evaluation = false,
  DateTime? graceEndsAt,
  bool clockSetBack = false,
  bool noExpiry = false,
}) => CruxLicenseStatus(
  activation: activation,
  grant: LicenseGrant(
    issuerId: 'keygen',
    tier: tier,
    products: const {CruxProduct.waveCrux},
    licenseId: 'lic-1',
    expiry: noExpiry ? null : _expiry,
    isEvaluation: evaluation,
  ),
  graceEndsAt: graceEndsAt,
  clockSetBack: clockSetBack,
);

class _Actions extends UnsupportedLicenseActions {
  _Actions();

  /// Purchase-page opens, in a list so the class stays shallowly immutable.
  final List<String> purchases = <String>[];

  @override
  bool get supportsPurchaseLinks => true;

  @override
  Future<CruxLicenseActionResult> openPurchasePage() async {
    purchases.add('pricing');
    return const LicenseActionSucceeded();
  }
}

/// A stateful page standing in for the routed app under the strip.
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        autofocus: true,
        onPressed: () => setState(() => count++),
        child: Text('Pressed $count'),
      ),
    ),
  );
}

void main() {
  const strings = CruxLicenseExpiryStringsEn();

  late List<String> opened;
  late InMemoryLicenseNoticeMemory memory;
  setUp(() {
    opened = <String>[];
    memory = InMemoryLicenseNoticeMemory();
  });

  Future<void> launch(
    WidgetTester tester, {
    required CruxLicenseStatus status,
    required DateTime now,
    bool managed = false,
    CruxLicenseActions actions = const UnsupportedLicenseActions(),
    Key? key,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        key: key,
        overrides: [
          licenseStatusProvider.overrideWithValue(status),
          licenseManagedByOrganizationProvider.overrideWithValue(managed),
          licenseClockProvider.overrideWithValue(() => now),
          licenseNoticeMemoryProvider.overrideWithValue(memory),
          licenseActionsProvider.overrideWithValue(actions),
        ],
        child: MaterialApp(
          builder: (context, child) => CruxLicenseExpiryGate(
            onOpenLicenseSettings: () => opened.add('license'),
            child: child!,
          ),
          home: const _Page(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder banner() => find.byType(CruxLicenseExpiryBanner);

  group('shows nothing', () {
    testWidgets('at Open Core', (tester) async {
      await launch(
        tester,
        status: CruxLicenseStatus.openCore,
        now: _expiry.subtract(const Duration(days: 1)),
      );
      expect(banner(), findsNothing);
      expect(find.text('Pressed 0'), findsOneWidget);
    });

    testWidgets('for a term licence with no expiry date', (tester) async {
      await launch(
        tester,
        status: _status(CruxLicenseActivation.active, noExpiry: true),
        now: _expiry,
      );
      expect(banner(), findsNothing);
    });

    testWidgets('more than 30 days before expiry', (tester) async {
      await launch(
        tester,
        status: _status(CruxLicenseActivation.active),
        now: _expiry.subtract(const Duration(days: 31)),
      );
      expect(banner(), findsNothing);
    });
  });

  group('before expiry', () {
    testWidgets('30 days before, it names the tier and the date', (
      tester,
    ) async {
      await launch(
        tester,
        status: _status(CruxLicenseActivation.active),
        now: _expiry.subtract(const Duration(days: 30)),
      );
      expect(
        find.text(strings.expiringMessage('Pro', _date(_expiry))),
        findsOneWidget,
      );
    });

    testWidgets('inside the window, the button opens Settings → License', (
      tester,
    ) async {
      await launch(
        tester,
        status: _status(CruxLicenseActivation.active),
        now: _expiry.subtract(const Duration(days: 5)),
      );
      await tester.tap(
        find.byKey(CruxLicenseExpiryBanner.openSettingsButtonKey),
      );
      expect(opened, ['license']);
      expect(find.byKey(CruxLicenseExpiryBanner.buyButtonKey), findsNothing);
    });

    testWidgets('dismissed for the session, back at the next launch', (
      tester,
    ) async {
      final status = _status(CruxLicenseActivation.active);
      final now = _expiry.subtract(const Duration(days: 5));
      await launch(tester, status: status, now: now);
      await tester.tap(find.byKey(CruxLicenseExpiryBanner.dismissButtonKey));
      await tester.pumpAndSettle();
      expect(banner(), findsNothing);

      // Same session: a rebuild, a resume, the same licence again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(banner(), findsNothing);

      // A fresh app: the strip is back.
      await launch(tester, status: status, now: now, key: UniqueKey());
      expect(banner(), findsOneWidget);
    });

    testWidgets('an evaluation counts down from 14 days, not 30', (
      tester,
    ) async {
      final status = _status(
        CruxLicenseActivation.active,
        tier: LicenseTier.enterprise,
        evaluation: true,
      );
      await launch(
        tester,
        status: status,
        now: _expiry.subtract(const Duration(days: 20)),
      );
      expect(banner(), findsNothing);

      await launch(
        tester,
        status: status,
        now: _expiry.subtract(const Duration(days: 14)),
        key: UniqueKey(),
      );
      expect(
        find.text(
          strings.evaluationEndingMessage('Enterprise', _date(_expiry)),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('in grace, worded as overdue, with the days the panel shows', (
    tester,
  ) async {
    final now = _expiry.add(const Duration(days: 10));
    final status = _status(
      CruxLicenseActivation.grace,
      graceEndsAt: _expiry.add(const Duration(days: 30)),
    );
    await launch(tester, status: status, now: now);
    expect(
      find.text(
        strings.graceMessage(
          'Pro',
          _date(_expiry),
          status.graceDaysRemainingAt(now)!,
        ),
      ),
      findsOneWidget,
    );
    expect(status.graceDaysRemainingAt(now), 20);
  });

  group('after grace', () {
    testWidgets('one notice on the drop to Open Core, not one per launch', (
      tester,
    ) async {
      final status = _status(CruxLicenseActivation.expired);
      final now = _expiry.add(const Duration(days: 40));
      await launch(tester, status: status, now: now);
      expect(
        find.text(strings.endedMessage('Pro', _date(_expiry))),
        findsOneWidget,
      );

      await launch(tester, status: status, now: now, key: UniqueKey());
      expect(banner(), findsNothing, reason: 'already shown on this machine');
    });

    testWidgets('an evaluation that ended says where to buy', (tester) async {
      final actions = _Actions();
      await launch(
        tester,
        status: _status(
          CruxLicenseActivation.expired,
          tier: LicenseTier.enterprise,
          evaluation: true,
        ),
        now: _expiry.add(const Duration(days: 1)),
        actions: actions,
      );
      expect(
        find.text(
          strings.evaluationEndedMessage('Enterprise', _date(_expiry)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(CruxLicenseExpiryBanner.buyButtonKey));
      expect(actions.purchases, ['pricing']);
    });

    testWidgets('an evaluation ended by its clock says why', (tester) async {
      await launch(
        tester,
        status: _status(
          CruxLicenseActivation.expired,
          tier: LicenseTier.enterprise,
          evaluation: true,
          clockSetBack: true,
        ),
        now: DateTime.utc(2026, 9),
      );
      expect(
        find.text(strings.evaluationClockMessage('Enterprise')),
        findsOneWidget,
      );
    });
  });

  group('a policy-deployed licence points to the administrator', () {
    testWidgets('before expiry', (tester) async {
      await launch(
        tester,
        status: _status(
          CruxLicenseActivation.active,
          tier: LicenseTier.enterprise,
        ),
        now: _expiry.subtract(const Duration(days: 2)),
        managed: true,
        actions: _Actions(),
      );
      expect(
        find.text(
          strings.managedExpiringMessage('Enterprise', _date(_expiry)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('in grace', (tester) async {
      final now = _expiry.add(const Duration(days: 1));
      final status = _status(
        CruxLicenseActivation.grace,
        tier: LicenseTier.enterprise,
        graceEndsAt: _expiry.add(const Duration(days: 90)),
      );
      await launch(tester, status: status, now: now, managed: true);
      expect(
        find.text(
          strings.managedGraceMessage(
            'Enterprise',
            _date(_expiry),
            status.graceDaysRemainingAt(now)!,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('after grace, with no purchase button', (tester) async {
      await launch(
        tester,
        status: _status(
          CruxLicenseActivation.expired,
          tier: LicenseTier.enterprise,
          evaluation: true,
        ),
        now: _expiry.add(const Duration(days: 100)),
        managed: true,
        actions: _Actions(),
      );
      expect(
        find.text(strings.managedEndedMessage('Enterprise', _date(_expiry))),
        findsOneWidget,
      );
      expect(find.byKey(CruxLicenseExpiryBanner.buyButtonKey), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('announced once when it appears, not on every rebuild', (
      tester,
    ) async {
      final recorder = AnnouncementRecorder.attach(tester);
      final status = _status(CruxLicenseActivation.active);
      final message = strings.expiringMessage('Pro', _date(_expiry));
      await launch(
        tester,
        status: status,
        now: _expiry.subtract(const Duration(days: 5)),
      );
      expect(recorder.messages, [message]);

      // Rebuilds: the clock moves on, the app resumes, the page repaints.
      await launch(
        tester,
        status: status,
        now: _expiry.subtract(const Duration(days: 4)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pressed 0'));
      await tester.pumpAndSettle();
      expect(recorder.messages, [message]);
    });

    testWidgets('never takes focus from the app', (tester) async {
      await launch(
        tester,
        status: _status(CruxLicenseActivation.expired),
        now: _expiry.add(const Duration(days: 40)),
      );
      expect(banner(), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(
          of: find.byWidget(focused!.widget),
          matching: banner(),
        ),
        findsNothing,
      );
    });

    testWidgets('its controls are each one named Tab stop', (tester) async {
      // The strip alone: in an app it sits above the Navigator, outside the
      // route's focus scope, so this walks it on its own.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CruxLicenseExpiryBanner(
              message: strings.endedMessage('Pro', _date(_expiry)),
              urgent: true,
              openSettingsLabel: strings.openSettingsAction,
              onOpenSettings: () {},
              buyLabel: strings.buyAction,
              onBuy: () {},
              dismissLabel: strings.dismissLabel,
              onDismiss: () {},
            ),
          ),
        ),
      );
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.transcript, contains(strings.openSettingsAction));
      expect(walk.transcript, contains(strings.buyAction));
      expect(walk.transcript, contains(strings.dismissLabel));
      handle.dispose();
    });
  });

  testWidgets('the app under the strip keeps its state when it goes', (
    tester,
  ) async {
    await launch(
      tester,
      status: _status(CruxLicenseActivation.active),
      now: _expiry.subtract(const Duration(days: 5)),
    );
    await tester.tap(find.text('Pressed 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CruxLicenseExpiryBanner.dismissButtonKey));
    await tester.pumpAndSettle();
    expect(banner(), findsNothing);
    expect(find.text('Pressed 1'), findsOneWidget);
  });

  testWidgets('a narrow window wraps the actions under the message', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await launch(
      tester,
      status: _status(
        CruxLicenseActivation.expired,
        tier: LicenseTier.enterprise,
        evaluation: true,
      ),
      now: _expiry.add(const Duration(days: 1)),
      actions: _Actions(),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(CruxLicenseExpiryBanner.buyButtonKey), findsOneWidget);
  });
}
