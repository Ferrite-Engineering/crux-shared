// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = CruxGlowPalette(
    background: Colors.purple,
    outer: Colors.cyan,
    middle: Colors.amber,
    inner: Colors.cyan,
    innerCore: Colors.white,
  );

  Widget host(Widget child, {Brightness brightness = Brightness.dark}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: child)),
      );

  group('CruxGlowingAppIcon', () {
    testWidgets('renders the supplied icon inside the glow box and animates '
        'without exceptions', (tester) async {
      await tester.pumpWidget(
        host(
          const CruxGlowingAppIcon(
            icon: FlutterLogo(size: 72),
            palette: palette,
            size: 72,
          ),
        ),
      );
      expect(find.byType(FlutterLogo), findsOneWidget);
      // The glow box reserves extra space around the icon.
      final box = tester.getSize(find.byType(CruxGlowingAppIcon));
      expect(box.width, greaterThan(72));
      // Let both controllers tick a few frames — a painter error would
      // surface as an exception here.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in light theme (reduced but visible aura)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CruxGlowingAppIcon(
            icon: FlutterLogo(size: 72),
            palette: palette,
            size: 72,
          ),
          brightness: Brightness.light,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    test('fromSeed derives distinct hue-shifted layers around the brand', () {
      final p = CruxGlowPalette.fromSeed(const Color(0xFFD4A017));
      expect(p.outer, const Color(0xFFD4A017));
      expect(p.middle, isNot(p.outer));
      expect(p.background, isNot(p.outer));
      // The core is a bright near-white tint.
      expect(HSLColor.fromColor(p.innerCore).lightness, greaterThan(0.8));
    });
  });

  group('EmptyCanvasState header slot', () {
    testWidgets('renders the header centered above the title', (tester) async {
      await tester.pumpWidget(
        host(
          const EmptyCanvasState(
            header: FlutterLogo(size: 40),
            title: 'Welcome',
          ),
        ),
      );
      expect(find.byType(FlutterLogo), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      final headerY = tester.getCenter(find.byType(FlutterLogo)).dy;
      final titleY = tester.getCenter(find.text('Welcome')).dy;
      expect(headerY, lessThan(titleY));
    });

    testWidgets('omitting the header keeps the legacy composition', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const EmptyCanvasState(title: 'Welcome')),
      );
      expect(find.text('Welcome'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
