// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  int days = 3,
  VoidCallback? onDownload,
  VoidCallback? onDismiss,
  CruxBetaExpirySizing sizing = const CruxBetaExpirySizing(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CruxBetaExpiryBanner(
          daysRemaining: days,
          onDownload: onDownload ?? () {},
          onDismiss: onDismiss ?? () {},
          sizing: sizing,
        ),
      ),
    ),
  );
}

void main() {
  group('CruxBetaExpiryBanner', () {
    testWidgets('renders the day count and the download action', (
      tester,
    ) async {
      await _pump(tester, days: 5);
      expect(find.text('This beta build expires in 5 days.'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('uses the singular message at one day', (tester) async {
      await _pump(tester, days: 1);
      expect(find.text('This beta build expires tomorrow.'), findsOneWidget);
    });

    testWidgets('the callbacks fire from their keyed controls', (tester) async {
      var downloaded = 0;
      var dismissed = 0;
      await _pump(
        tester,
        onDownload: () => downloaded++,
        onDismiss: () => dismissed++,
      );

      await tester.tap(find.byKey(CruxBetaExpiryBanner.downloadButtonKey));
      await tester.tap(find.byKey(CruxBetaExpiryBanner.dismissButtonKey));
      await tester.pump();

      expect(downloaded, 1);
      expect(dismissed, 1);
    });

    testWidgets('the dismiss button carries an accessible name', (
      tester,
    ) async {
      // The regression this pins: the button has no visible label and cannot
      // use a Tooltip (it renders above the Navigator, so there is no Overlay
      // ancestor). Semantics is the only thing standing between it and being
      // announced as an unnamed "button".
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        find.bySemanticsLabel('Dismiss'),
        findsOneWidget,
        reason:
            'The dismiss control must keep its Semantics wrapper — a Tooltip '
            'cannot work on this surface.',
      );
      handle.dispose();
    });

    testWidgets('honours the 44 dp touch-target floor by default', (
      tester,
    ) async {
      await _pump(tester);
      final size = tester.getSize(
        find.byKey(CruxBetaExpiryBanner.dismissButtonKey),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('a product can scale the strip up for touch', (tester) async {
      // WaveCrux is the only product with a device-class metrics system; this
      // is the seam it uses.
      await _pump(
        tester,
        sizing: const CruxBetaExpirySizing(
          iconSize: 28,
          touchTarget: 56,
          bodyTextSize: 18,
        ),
      );
      final size = tester.getSize(
        find.byKey(CruxBetaExpiryBanner.dismissButtonKey),
      );
      expect(size.width, greaterThanOrEqualTo(56));
    });
  });
}
