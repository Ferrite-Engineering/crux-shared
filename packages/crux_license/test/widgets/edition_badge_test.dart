// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CustomStrings extends LicenseBadgeStrings {
  const _CustomStrings();
  @override
  String get tierBadgePro => 'PRO';
  @override
  String get tierBadgeProSemantic => 'pro feature';
  @override
  String get tierBadgeEnterprise => 'ENT';
  @override
  String get tierBadgeEnterpriseSemantic => 'ent feature';
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

/// Mount [child] with `licenseTierProvider` resolving to [tier].
Widget _wrap(Widget child, {LicenseTier tier = LicenseTier.openCore}) =>
    ProviderScope(
      overrides: [licenseTierProvider.overrideWithValue(tier)],
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('EditionBadge', () {
    // FIRST, because it is the property that makes this widget safe to mount
    // unconditionally in shared chrome — the status bar's trailing slot, the
    // About dialog — without any call site inspecting the tier. If this ever
    // breaks, every open-core build starts advertising an edition it does not
    // have.
    testWidgets('renders NOTHING at open core', (tester) async {
      await tester.pumpWidget(_wrap(const EditionBadge()));

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Container), findsNothing);
      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(tester.getSize(find.byType(SizedBox)), Size.zero);
    });

    testWidgets('renders PRO for a Pro licence', (tester) async {
      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.pro),
      );
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('renders ENT for an Enterprise licence', (tester) async {
      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.enterprise),
      );
      expect(find.text('ENT'), findsOneWidget);
    });

    testWidgets('renders EDU for an Educational licence', (tester) async {
      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.edu),
      );
      expect(find.text('EDU'), findsOneWidget);
    });

    testWidgets('EDU keeps its own colour, distinct from PRO', (tester) async {
      // EDU is not "Pro that costs nothing" — it carries non-commercial terms
      // and an annual renewal, and the visual distinction survived the
      // generalization from EducationalBadge.
      Color colorFor(WidgetTester t) =>
          (t.widget<Container>(find.byType(Container)).decoration!
                  as BoxDecoration)
              .color!;

      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.edu),
      );
      final edu = colorFor(tester);

      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.pro),
      );
      final pro = colorFor(tester);

      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.enterprise),
      );
      final ent = colorFor(tester);

      expect(edu, isNot(pro));
      expect(edu, isNot(ent));
      expect(pro, isNot(ent));
    });

    testWidgets('it follows the provider, not a constructor argument', (
      tester,
    ) async {
      // The whole reason for the generalization: a statement about what the
      // user OWNS has one source. Changing the provider changes the badge with
      // no call-site involvement at all.
      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.pro),
      );
      expect(find.text('PRO'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const EditionBadge(), tier: LicenseTier.enterprise),
      );
      expect(find.text('ENT'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('an explicit tier overrides the provider', (tester) async {
      // The licence panel's case: it holds status.tier, which the provider is
      // derived from, and must not render a chip disagreeing with the label
      // beside it.
      await tester.pumpWidget(
        _wrap(const EditionBadge(tier: LicenseTier.enterprise)),
      );
      expect(find.text('ENT'), findsOneWidget);
    });

    group('semantics say what you OWN, not what a feature requires', () {
      // "Pro edition" and "requires Pro" are different sentences. A
      // screen-reader user must not hear the second when the screen is saying
      // the first.
      for (final (tier, expected) in const <(LicenseTier, String)>[
        (LicenseTier.edu, '教育エディション'),
        (LicenseTier.pro, 'プロエディション'),
        (LicenseTier.enterprise, 'エンタープライズエディション'),
      ]) {
        testWidgets('${tier.name} reads as an edition', (tester) async {
          await tester.pumpWidget(
            _wrap(
              const EditionBadge(strings: _CustomStrings()),
              tier: tier,
            ),
          );
          expect(
            tester.getSemantics(find.byType(EditionBadge)).label,
            expected,
          );
        });
      }

      testWidgets('the edition phrase is not the feature phrase', (
        tester,
      ) async {
        const strings = _CustomStrings();
        await tester.pumpWidget(
          _wrap(
            const EditionBadge(strings: strings),
            tier: LicenseTier.pro,
          ),
        );
        final label = tester.getSemantics(find.byType(EditionBadge)).label;
        expect(label, strings.editionBadgeProSemantic);
        expect(
          label,
          isNot(strings.tierBadgeProSemantic),
          reason: 'the feature-tier phrasing must not leak onto an edition',
        );
      });
    });
  });
}
