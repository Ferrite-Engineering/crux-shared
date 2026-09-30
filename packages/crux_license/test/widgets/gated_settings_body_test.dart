// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = Key('real-body');

Widget _host({
  required bool beta,
  required LicenseTier tier,
  LicenseTier requiredTier = LicenseTier.pro,
  CruxLicenseActions? actions,
  CruxUpgradeDialogStrings strings = const CruxUpgradeDialogStringsEn(),
  LicenseBadgeStrings badgeStrings = const LicenseBadgeStringsEn(),
}) {
  return ProviderScope(
    overrides: [
      betaPeriodProvider.overrideWithValue(beta),
      licenseTierProvider.overrideWithValue(tier),
      if (actions != null) licenseActionsProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CruxGatedSettingsBody(
          requiredTier: requiredTier,
          featureName: 'Collaboration',
          strings: strings,
          badgeStrings: badgeStrings,
          child: const SizedBox(key: _child),
        ),
      ),
    ),
  );
}

void main() {
  group('CruxGatedSettingsBody', () {
    testWidgets('renders the child while the beta is on, whatever the tier', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(beta: true, tier: LicenseTier.openCore),
      );
      expect(find.byKey(_child), findsOneWidget);
      expect(find.byType(FeatureTierBadge), findsNothing);
    });

    testWidgets('locks an Open Core user out of a Pro body post-beta', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(beta: false, tier: LicenseTier.openCore),
      );
      expect(find.byKey(_child), findsNothing);
      expect(find.text('Collaboration'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('“Collaboration” requires Pro.'), findsOneWidget);
      // Open core has nothing to sell, so there is no button that goes
      // nowhere.
      expect(find.text('See pricing'), findsNothing);
    });

    testWidgets('renders the child for a Pro user post-beta', (tester) async {
      await tester.pumpWidget(_host(beta: false, tier: LicenseTier.pro));
      expect(find.byKey(_child), findsOneWidget);
    });

    testWidgets('EDU is feature-equivalent to Pro', (tester) async {
      await tester.pumpWidget(_host(beta: false, tier: LicenseTier.edu));
      expect(find.byKey(_child), findsOneWidget);
    });

    testWidgets('a Pro user is locked out of an Enterprise body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          beta: false,
          tier: LicenseTier.pro,
          requiredTier: LicenseTier.enterprise,
        ),
      );
      expect(find.byKey(_child), findsNothing);
      expect(find.text('ENT'), findsOneWidget);
      expect(
        find.text('“Collaboration” requires Enterprise.'),
        findsOneWidget,
      );
    });

    testWidgets('an Enterprise user unlocks an Enterprise body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          beta: false,
          tier: LicenseTier.enterprise,
          requiredTier: LicenseTier.enterprise,
        ),
      );
      expect(find.byKey(_child), findsOneWidget);
    });

    testWidgets('offers See pricing when the build can sell, and it opens '
        'the purchase page', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          beta: false,
          tier: LicenseTier.openCore,
          actions: _Selling(() => opened++),
        ),
      );
      expect(find.text('See pricing'), findsOneWidget);
      await tester.tap(find.text('See pricing'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('uses the caller-supplied strings, never baked-in English', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          beta: false,
          tier: LicenseTier.openCore,
          actions: _Selling(() {}),
          strings: const _CustomStrings(),
          badgeStrings: const _CustomBadgeStrings(),
        ),
      );
      expect(find.text('プロ'), findsOneWidget);
      expect(find.text('Collaboration には プロ が必要です'), findsOneWidget);
      expect(find.text('価格を見る'), findsOneWidget);
      expect(find.text('See pricing'), findsNothing);
    });

    testWidgets('swaps the locked panel for the body when a licence lands', (
      tester,
    ) async {
      final tier = NotifierProvider<_MutableTier, LicenseTier>(
        _MutableTier.new,
      );
      final container = ProviderContainer(
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith((ref) => ref.watch(tier)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CruxGatedSettingsBody(
                requiredTier: LicenseTier.pro,
                featureName: 'Collaboration',
                child: SizedBox(key: _child),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(_child), findsNothing);

      container.read(tier.notifier).value = LicenseTier.pro;
      await tester.pump();
      expect(find.byKey(_child), findsOneWidget);
    });
  });

  group('cruxGatedSettingsCategory', () {
    testWidgets('carries id, icon and label through, and gates the body', (
      tester,
    ) async {
      final category = cruxGatedSettingsCategory(
        id: 'pro.collaboration',
        icon: Icons.groups_outlined,
        requiredTier: LicenseTier.enterprise,
        labelBuilder: (_) => 'Collaboration',
        bodyBuilder: (_) => const SizedBox(key: _child),
      );
      expect(category.id, 'pro.collaboration');
      expect(category.icon, Icons.groups_outlined);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            betaPeriodProvider.overrideWithValue(false),
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final shell = category.toCategory(context);
                  expect(shell.id, 'pro.collaboration');
                  expect(shell.title, 'Collaboration');
                  return shell.content;
                },
              ),
            ),
          ),
        ),
      );
      // The rail label is the locked panel's feature name, so the two
      // surfaces cannot disagree about what this is.
      expect(find.byKey(_child), findsNothing);
      expect(find.text('Collaboration'), findsOneWidget);
      expect(find.text('ENT'), findsOneWidget);
      expect(find.byType(CruxSettingsSectionCard), findsOneWidget);
    });
  });
}

/// Actions from a build that has commerce wiring.
class _Selling extends UnsupportedLicenseActions {
  const _Selling(this.onOpen);

  final void Function() onOpen;

  @override
  bool get supportsPurchaseLinks => true;

  @override
  Future<CruxLicenseActionResult> openPurchasePage() async {
    onOpen();
    return const LicenseActionSucceeded();
  }
}

class _MutableTier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get value => state;

  set value(LicenseTier tier) => state = tier;
}

class _CustomStrings extends CruxUpgradeDialogStrings {
  const _CustomStrings();
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
