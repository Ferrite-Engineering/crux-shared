// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:crux_license/crux_license.dart';
import 'package:crux_license/src/widgets/license_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The status-bar EDU chip and the export mark: both say an educational
/// licence is for non-commercial use, and both are silent for every other
/// tier.
void main() {
  LicenseGrant grant(
    LicenseTier tier, {
    String? email = 'student@example.edu',
  }) => LicenseGrant(
    issuerId: kEduLicenseIssuerId,
    tier: tier,
    products: CruxProduct.values.toSet(),
    licenseId: 'lic-1',
    email: email,
    expiry: DateTime.utc(2027, 8, 2, 12),
  );

  CruxLicenseStatus status(
    LicenseTier tier, {
    CruxLicenseActivation activation = CruxLicenseActivation.active,
    String? email = 'student@example.edu',
  }) => CruxLicenseStatus(
    activation: activation,
    grant: grant(tier, email: email),
  );

  Widget host(CruxLicenseStatus s, {VoidCallback? onTap}) => ProviderScope(
    overrides: [licenseStatusProvider.overrideWithValue(s)],
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: CruxEduStatusChip(onTap: onTap)),
      ),
    ),
  );

  group('CruxEduStatusChip', () {
    testWidgets('renders nothing at open core', (tester) async {
      await tester.pumpWidget(host(CruxLicenseStatus.openCore));
      expect(find.byType(EditionBadge), findsNothing);
      expect(find.textContaining('Non-commercial'), findsNothing);
    });

    for (final tier in [LicenseTier.pro, LicenseTier.enterprise]) {
      testWidgets('renders nothing at ${tier.name}', (tester) async {
        await tester.pumpWidget(host(status(tier)));
        expect(find.byType(EditionBadge), findsNothing);
        expect(find.textContaining('Non-commercial'), findsNothing);
      });
    }

    testWidgets('renders nothing once an EDU licence has expired', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status(LicenseTier.edu, activation: CruxLicenseActivation.expired),
        ),
      );
      expect(find.byType(EditionBadge), findsNothing);
    });

    testWidgets('EDU: the chip, non-commercial use and the address', (
      tester,
    ) async {
      await tester.pumpWidget(host(status(LicenseTier.edu)));
      expect(find.text('EDU'), findsOneWidget);
      expect(
        find.text('Non-commercial use · student@example.edu'),
        findsOneWidget,
      );
    });

    testWidgets('EDU in grace still shows the chip', (tester) async {
      await tester.pumpWidget(
        host(status(LicenseTier.edu, activation: CruxLicenseActivation.grace)),
      );
      expect(find.text('EDU'), findsOneWidget);
    });

    testWidgets('EDU with no recorded address: the label alone', (
      tester,
    ) async {
      await tester.pumpWidget(host(status(LicenseTier.edu, email: null)));
      expect(find.text('Non-commercial use'), findsOneWidget);
    });

    testWidgets('the tooltip names the holder, the terms and the end date', (
      tester,
    ) async {
      await tester.pumpWidget(host(status(LicenseTier.edu)));
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('student@example.edu'));
      expect(tooltip.message, contains('non-commercial'));
      expect(
        tooltip.message,
        contains(formatLicenseDate(DateTime.utc(2027, 8, 2, 12))),
      );
    });

    testWidgets('screen readers hear the tooltip sentence, once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(status(LicenseTier.edu)));
      expect(
        find.bySemanticsLabel(RegExp('Educational license for student@')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Educational edition'), findsNothing);
      handle.dispose();
    });

    testWidgets('a click calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(status(LicenseTier.edu), onTap: () => taps++),
      );
      await tester.tap(find.text('EDU'));
      expect(taps, 1);
    });

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets('Tab reaches the chip and ${key.debugName} activates it', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(
          host(status(LicenseTier.edu), onTap: () => taps++),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(taps, 1);
      });
    }

    testWidgets('without onTap the chip takes no focus', (tester) async {
      await tester.pumpWidget(host(status(LicenseTier.edu)));
      expect(find.byType(FocusableActionDetector), findsNothing);
    });

    testWidgets('a long address is ellipsized, not overflowed', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          status(
            LicenseTier.edu,
            email: '${'a' * 120}@engineering.example.edu',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final label = find.textContaining('Non-commercial use ·');
      expect(tester.getSize(label).width, lessThanOrEqualTo(320));
    });
  });

  group('cruxEduExportMark', () {
    test('null for every tier but EDU', () {
      expect(cruxEduExportMark(CruxLicenseStatus.openCore, 'WaveCrux'), isNull);
      expect(cruxEduExportMark(status(LicenseTier.pro), 'WaveCrux'), isNull);
      expect(
        cruxEduExportMark(status(LicenseTier.enterprise), 'WaveCrux'),
        isNull,
      );
    });

    test('EDU: names the product and the terms, never the address', () {
      final mark = cruxEduExportMark(status(LicenseTier.edu), 'NetCrux');
      expect(mark, 'Made with NetCrux Educational · Non-commercial use only');
      expect(mark, isNot(contains('@')));
    });
  });

  group('paintCruxEduExportMark', () {
    test('paints inside the export without throwing', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      paintCruxEduExportMark(
        canvas,
        const Size(800, 400),
        'Made with WaveCrux Educational · Non-commercial use only',
      );
      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, greaterThan(0));
      picture.dispose();
    });

    test('a canvas narrower than the mark still paints', () {
      final recorder = ui.PictureRecorder();
      paintCruxEduExportMark(
        Canvas(recorder),
        const Size(40, 20),
        'Made with WaveCrux Educational · Non-commercial use only',
      );
      recorder.endRecording().dispose();
    });
  });
}
