// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxDesktopTokens', () {
    test('the defaults are the Crux Desktop values', () {
      const t = CruxDesktopTokens();
      expect(t.controlHeight, 28);
      expect(t.denseControlHeight, 24);
      expect(t.rowHeight, 24);
      expect(t.twoLineRowHeight, 40);
      expect(t.controlRadius, 4);
      expect(t.menuRadius, 6);
      expect(t.dialogRadius, 8);
      expect(t.focusRingWidth, 1.5);
      expect(t.scrimOpacity, 0.18);
      expect(t.scrimColor, Colors.black.withValues(alpha: 0.18));
    });

    test('high contrast changes only the focus ring', () {
      const hc = CruxDesktopTokens.highContrast();
      expect(hc.focusRingWidth, 2.5);
      expect(hc, const CruxDesktopTokens().copyWith(focusRingWidth: 2.5));
      expect(hc, isNot(const CruxDesktopTokens()));
    });

    test('copyWith replaces each field and keeps the rest', () {
      const base = CruxDesktopTokens();
      final all = base.copyWith(
        controlHeight: 1,
        denseControlHeight: 2,
        rowHeight: 3,
        twoLineRowHeight: 4,
        controlRadius: 5,
        menuRadius: 6,
        dialogRadius: 7,
        focusRingWidth: 8,
        scrimOpacity: 0.5,
        bodyFontSize: 9,
        secondaryFontSize: 10,
        titleFontSize: 11,
        toastBottomInset: 12,
        toastMaxWidth: 13,
      );
      expect(
        [
          all.controlHeight,
          all.denseControlHeight,
          all.rowHeight,
          all.twoLineRowHeight,
          all.controlRadius,
          all.menuRadius,
          all.dialogRadius,
          all.focusRingWidth,
          all.scrimOpacity,
          all.bodyFontSize,
          all.secondaryFontSize,
          all.titleFontSize,
          all.toastBottomInset,
          all.toastMaxWidth,
        ],
        [1, 2, 3, 4, 5, 6, 7, 8, 0.5, 9, 10, 11, 12, 13],
      );
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
    });

    test('lerp switches at the midpoint rather than interpolating', () {
      const a = CruxDesktopTokens();
      const b = CruxDesktopTokens.highContrast();
      expect(a.lerp(b, 0.25), a);
      expect(a.lerp(b, 0.75), b);
      expect(a.lerp(null, 0.75), a);
    });

    testWidgets('of / isDesktop read the ambient theme', (tester) async {
      late BuildContext desktop;
      late BuildContext phone;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Theme(
                data: ThemeData(
                  extensions: const <ThemeExtension<dynamic>>[
                    CruxDesktopTokens(),
                  ],
                ),
                child: Builder(
                  builder: (c) {
                    desktop = c;
                    return const SizedBox();
                  },
                ),
              ),
              Builder(
                builder: (c) {
                  phone = c;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      expect(CruxDesktopTokens.isDesktop(desktop), isTrue);
      expect(CruxDesktopTokens.of(desktop), const CruxDesktopTokens());
      expect(CruxDesktopTokens.isDesktop(phone), isFalse);
      expect(CruxDesktopTokens.of(phone), isNull);
    });
  });

  group('CruxDialogAction roles', () {
    Future<void> pump(WidgetTester tester, CruxDialogActionRole role) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CruxDialogAction(
                label: 'Go',
                role: role,
                onPressed: () {},
              ),
            ),
          ),
        );

    testWidgets('each role draws its button family', (tester) async {
      await pump(tester, CruxDialogActionRole.secondary);
      expect(find.byType(OutlinedButton), findsOneWidget);
      await pump(tester, CruxDialogActionRole.primary);
      expect(find.byType(FilledButton), findsOneWidget);
      await pump(tester, CruxDialogActionRole.tertiary);
      expect(find.byType(TextButton), findsOneWidget);
      await pump(tester, CruxDialogActionRole.destructive);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  testWidgets('hideCruxSnack retires the phone snack bar', (tester) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showCruxInfoSnack(host, 'Checking');
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    hideCruxSnack(host);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
