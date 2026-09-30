// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CustomStrings extends LicenseBadgeStrings {
  const _CustomStrings();
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

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('FeatureTierBadge', () {
    testWidgets('renders empty SizedBox for openCore', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FeatureTierBadge(requiredTier: LicenseTier.openCore),
        ),
      );

      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets(
      'renders empty SizedBox for edu (not a feature-required tier)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const FeatureTierBadge(requiredTier: LicenseTier.edu),
          ),
        );

        expect(find.text('EDU'), findsNothing);
        expect(find.byType(Container), findsNothing);
      },
    );

    testWidgets('renders PRO chip with English defaults', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FeatureTierBadge(requiredTier: LicenseTier.pro),
        ),
      );

      expect(find.text('PRO'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(FeatureTierBadge)).label,
        contains('Pro tier feature'),
      );
    });

    testWidgets('renders ENT chip with English defaults', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FeatureTierBadge(requiredTier: LicenseTier.enterprise),
        ),
      );

      expect(find.text('ENT'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(FeatureTierBadge)).label,
        contains('Enterprise tier feature'),
      );
    });

    testWidgets('caller-supplied strings override English defaults', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const FeatureTierBadge(
            requiredTier: LicenseTier.pro,
            strings: _CustomStrings(),
          ),
        ),
      );

      expect(find.text('プロ'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('PRO chip uses primary scheme color', (tester) async {
      const seed = Color(0xFF112233);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
          home: const Scaffold(
            body: Center(
              child: FeatureTierBadge(requiredTier: LicenseTier.pro),
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(
        decoration.color,
        ColorScheme.fromSeed(seedColor: seed).primary,
      );
    });
  });
}
