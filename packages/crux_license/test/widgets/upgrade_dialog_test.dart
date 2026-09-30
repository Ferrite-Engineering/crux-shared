// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart' show ModalGuard;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CustomDialogStrings extends CruxUpgradeDialogStrings {
  const _CustomDialogStrings();
  @override
  String get title => 'アップグレードが必要';
  @override
  String body(String featureName, String tierName) =>
      '$featureName には $tierName が必要です';
  @override
  String get tierNamePro => 'プロ';
  @override
  String get tierNameEnterprise => 'エンタープライズ';
  @override
  String get dismissLabel => '閉じる';
  @override
  String get seePricingLabel => '価格を見る';
}

Widget _host({
  required LicenseTier requiredTier,
  CruxUpgradeDialogStrings l10n = const CruxUpgradeDialogStringsEn(),
  LicenseBadgeStrings strings = const LicenseBadgeStringsEn(),
  String? supplementalMessage,
  String featureName = 'Protocol Decoder',
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => CruxUpgradeDialog.show(
              context,
              featureName: featureName,
              requiredTier: requiredTier,
              strings: strings,
              l10n: l10n,
              supplementalMessage: supplementalMessage,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // The guard is process-global; a test that ends with a dialog still open
  // would otherwise leave its key held for the next one.
  setUp(ModalGuard.reset);

  group('CruxUpgradeDialog', () {
    testWidgets('renders title, body, badge, and dismiss for Pro', (
      tester,
    ) async {
      await _open(tester, _host(requiredTier: LicenseTier.pro));

      expect(find.text('Upgrade Required'), findsOneWidget);
      expect(find.text('“Protocol Decoder” requires Pro.'), findsOneWidget);
      // The FeatureTierBadge chip renders inside the title row.
      expect(find.byType(FeatureTierBadge), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('renders the Enterprise tier name and ENT chip', (
      tester,
    ) async {
      await _open(tester, _host(requiredTier: LicenseTier.enterprise));

      expect(
        find.text('“Protocol Decoder” requires Enterprise.'),
        findsOneWidget,
      );
      expect(find.text('ENT'), findsOneWidget);
    });

    testWidgets('injected strings replace every rendered text', (
      tester,
    ) async {
      await _open(
        tester,
        _host(
          requiredTier: LicenseTier.pro,
          l10n: const _CustomDialogStrings(),
        ),
      );

      expect(find.text('アップグレードが必要'), findsOneWidget);
      expect(find.text('Protocol Decoder には プロ が必要です'), findsOneWidget);
      expect(find.text('閉じる'), findsOneWidget);
      expect(find.text('Upgrade Required'), findsNothing);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('badge strings flow through to the chip', (tester) async {
      const badgeStrings = _CustomBadgeStrings();
      await _open(
        tester,
        _host(requiredTier: LicenseTier.pro, strings: badgeStrings),
      );

      expect(find.text('プロ'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('supplemental message renders when supplied', (tester) async {
      await _open(
        tester,
        _host(
          requiredTier: LicenseTier.pro,
          supplementalMessage: 'Manage your license in Settings.',
        ),
      );
      expect(find.text('Manage your license in Settings.'), findsOneWidget);
    });

    testWidgets('no supplemental text renders when omitted', (tester) async {
      await _open(tester, _host(requiredTier: LicenseTier.pro));
      // Only the title, body, and dismiss label render — two Text widgets
      // in the dialog content would indicate a phantom supplemental line.
      final dialogTexts = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      );
      expect(dialogTexts, findsNWidgets(4)); // title, badge, body, dismiss
    });

    testWidgets('the dismiss button closes the dialog', (tester) async {
      await _open(tester, _host(requiredTier: LicenseTier.pro));
      expect(find.byType(CruxUpgradeDialog), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(CruxUpgradeDialog), findsNothing);
    });

    testWidgets('a label ellipsis is dropped from the sentence', (
      tester,
    ) async {
      // Products name the feature with the label of the control that was
      // activated, and a menu label that opens more UI ends in one.
      await _open(
        tester,
        _host(requiredTier: LicenseTier.pro, featureName: 'Switch Project…'),
      );
      expect(find.text('“Switch Project” requires Pro.'), findsOneWidget);
    });

    testWidgets('three-dot ellipses are dropped the same way', (tester) async {
      await _open(
        tester,
        _host(requiredTier: LicenseTier.pro, featureName: 'Export PCAP...'),
      );
      expect(find.text('“Export PCAP” requires Pro.'), findsOneWidget);
    });
  });

  group('the opener is re-entrancy guarded', () {
    // A gated action is usually shortcut-reachable, and the shortcut layer
    // sits above the Navigator: key auto-repeat re-dispatches the denial
    // while the dialog is already up.
    testWidgets('a repeated denial while open stacks nothing', (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      Future<void> deny() => CruxUpgradeDialog.show(
        hostContext,
        featureName: 'Debug Advisor',
        requiredTier: LicenseTier.pro,
        strings: const LicenseBadgeStringsEn(),
        l10n: const CruxUpgradeDialogStringsEn(),
      );

      var suppressedReturned = false;
      unawaited(deny());
      unawaited(deny().then((_) => suppressedReturned = true));
      unawaited(deny());
      await tester.pumpAndSettle();

      expect(find.byType(CruxUpgradeDialog), findsOneWidget);
      expect(ModalGuard.isOpen(CruxUpgradeDialog.modalGuardKey), isTrue);
      expect(
        suppressedReturned,
        isTrue,
        reason: 'a suppressed call resolves at once rather than hanging',
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(CruxUpgradeDialog), findsNothing);
      expect(
        ModalGuard.isOpen(CruxUpgradeDialog.modalGuardKey),
        isFalse,
        reason: 'closing the dialog releases the guard',
      );

      unawaited(deny());
      await tester.pumpAndSettle();
      expect(
        find.byType(CruxUpgradeDialog),
        findsOneWidget,
        reason: 'the next denial after a close opens normally',
      );
    });
  });

  group('the pricing action', () {
    // Before paid licences went on sale there was nothing to buy; now a dialog
    // that says a feature needs Pro and offers no way to get Pro is a dead
    // end at the one moment a user is most willing to act.
    testWidgets('is absent when the build has nothing to sell', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CruxUpgradeDialog(
            featureName: 'Debug Advisor',
            requiredTier: LicenseTier.pro,
            strings: LicenseBadgeStringsEn(),
            l10n: CruxUpgradeDialogStringsEn(),
          ),
        ),
      );

      expect(
        find.text(const CruxUpgradeDialogStringsEn().seePricingLabel),
        findsNothing,
        reason: 'an open-core build must not show a button that goes nowhere',
      );
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('opens pricing and closes the dialog behind it', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CruxUpgradeDialog.show(
                  context,
                  featureName: 'Debug Advisor',
                  requiredTier: LicenseTier.pro,
                  strings: const LicenseBadgeStringsEn(),
                  l10n: const CruxUpgradeDialogStringsEn(),
                  onSeePricing: () async => opened++,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(const CruxUpgradeDialogStringsEn().seePricingLabel),
      );
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(
        find.byType(CruxUpgradeDialog),
        findsNothing,
        reason:
            'the pricing page opens in the browser; coming back to a modal '
            'you already dealt with is the bug this guards',
      );
    });

    testWidgets('resolves to null rather than throwing without a scope', (
      tester,
    ) async {
      // The caller is a deny path: the user has already been refused
      // something, and turning that refusal into a crash is strictly worse
      // than a dialog with no pricing button. A widget test that pumps the
      // dialog directly is the ordinary way to be here.
      Future<void> Function()? resolved;
      var threw = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              try {
                resolved = cruxSeePricingActionFor(context);
              } on Object {
                threw = true;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(threw, isFalse);
      expect(resolved, isNull);
    });

    testWidgets('resolves through the provider when a scope is present', (
      tester,
    ) async {
      Future<void> Function()? resolved;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [licenseActionsProvider.overrideWithValue(_Selling())],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                resolved = cruxSeePricingActionFor(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(resolved, isNotNull);
    });

    test('cruxSeePricingAction reflects what the build can do', () {
      expect(
        cruxSeePricingAction(const UnsupportedLicenseActions()),
        isNull,
        reason: 'open core has nothing to sell',
      );
      expect(cruxSeePricingAction(_Selling()), isNotNull);
    });
  });
}

/// Actions from a build that has commerce wiring.
class _Selling extends UnsupportedLicenseActions {
  @override
  bool get supportsPurchaseLinks => true;

  @override
  Future<CruxLicenseActionResult> openPurchasePage() async =>
      const LicenseActionSucceeded();
}

class _CustomBadgeStrings extends LicenseBadgeStrings {
  const _CustomBadgeStrings();
  @override
  String get tierBadgePro => 'プロ';
  @override
  String get tierBadgeProSemantic => 'プロ機能';
  @override
  String get tierBadgeEnterprise => 'エンタープライズ';
  @override
  String get tierBadgeEnterpriseSemantic => 'エンタープライズ機能';
  @override
  String get tierBadgeEdu => '教育';
  @override
  String get tierBadgeEduSemantic => '教育ライセンス';
  @override
  String get editionBadgeEduSemantic => '教育エディション';
  @override
  String get editionBadgeProSemantic => 'プロエディション';
  @override
  String get editionBadgeEnterpriseSemantic => 'エンタープライズエディション';
}
