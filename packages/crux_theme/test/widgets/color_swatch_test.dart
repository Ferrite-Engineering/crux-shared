// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxColorSwatch', () {
    testWidgets('renders with default size and a 44 dp hit area', (
      tester,
    ) async {
      const key = ValueKey('swatch');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CruxColorSwatch(key: key, color: Color(0xFFAABBCC)),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(key));
      // hit area must be at least 44 dp to honor touch-target guidance
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('larger size is honored', (tester) async {
      const key = ValueKey('swatch');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CruxColorSwatch(
                key: key,
                color: Color(0xFFAABBCC),
                size: 80,
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(key));
      expect(size.width, 80);
      expect(size.height, 80);
    });

    testWidgets('tapping with onColorPicked opens the picker dialog', (
      tester,
    ) async {
      var pickedCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CruxColorSwatch(
                color: const Color(0xFFAABBCC),
                onColorPicked: (_) => pickedCount++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(CruxColorSwatch));
      await tester.pump();
      const strings = ThemeAppearanceStringsEn();
      expect(find.text(strings.colorPickerDialogTitle), findsOneWidget);
      // dismiss without picking
      await tester.tap(find.text(strings.colorPickerCancelLabel));
      await tester.pump();
      expect(pickedCount, 0);
    });

    testWidgets('tapping without onColorPicked does not open the picker', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CruxColorSwatch(color: Color(0xFFAABBCC)),
            ),
          ),
        ),
      );
      // No InkWell should be present when the swatch is read-only.
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
