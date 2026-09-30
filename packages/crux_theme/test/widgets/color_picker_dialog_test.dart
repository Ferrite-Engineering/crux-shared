// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
// `ColorPickerDialog`, `colorFromHex` and `hexFromColor` are no longer
// exported from the barrel (no consumer referenced them). Testing
// an internal helper through its own library is the intended pattern.
import 'package:crux_theme/src/widgets/color_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColorPickerDialog', () {
    testWidgets('renders title, action labels, and slider labels', (
      tester,
    ) async {
      const strings = ThemeAppearanceStringsEn();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showColorPickerDialog(
                    context: context,
                    initialColor: const Color(0xFFAABBCC),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();

      expect(find.text(strings.colorPickerDialogTitle), findsOneWidget);
      expect(find.text(strings.colorPickerOkLabel), findsOneWidget);
      expect(find.text(strings.colorPickerCancelLabel), findsOneWidget);
      expect(find.text(strings.colorPickerHueLabel), findsOneWidget);
      expect(find.text(strings.colorPickerSaturationLabel), findsOneWidget);
      expect(find.text(strings.colorPickerValueLabel), findsOneWidget);
    });

    testWidgets('palette sections stage a tapped swatch and mark it '
        'selected', (tester) async {
      Color? result;
      const palette = ColorPickerPaletteSection(
        label: 'Palette',
        colors: [Color(0xFF112233), Color(0xFF445566)],
        swatchSize: 32,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showColorPickerDialog(
                      context: context,
                      initialColor: const Color(0xFFAABBCC),
                      paletteSections: const [palette],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.text('Palette'), findsOneWidget);
      // No swatch selected yet (staged color is not in the palette).
      expect(find.byIcon(Icons.check), findsNothing);

      // Tap the second swatch: it stages the color and gains the check.
      final swatches = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.child is Container,
      );
      await tester.tap(swatches.at(1));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);

      const strings = ThemeAppearanceStringsEn();
      await tester.tap(find.text(strings.colorPickerOkLabel));
      await tester.pumpAndSettle();
      expect(result, const Color(0xFF445566));
    });

    testWidgets('Cancel returns null', (tester) async {
      Color? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showColorPickerDialog(
                      context: context,
                      initialColor: const Color(0xFFAABBCC),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      const strings = ThemeAppearanceStringsEn();
      await tester.tap(find.text(strings.colorPickerCancelLabel));
      await tester.pump();
      expect(result, isNull);
    });

    testWidgets('OK returns the initial color when nothing is edited', (
      tester,
    ) async {
      Color? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showColorPickerDialog(
                      context: context,
                      initialColor: const Color(0xFFAABBCC),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      const strings = ThemeAppearanceStringsEn();
      await tester.tap(find.text(strings.colorPickerOkLabel));
      await tester.pump();
      expect(result, isNotNull);
      // initial alpha was 0xFF -- the staged value should round-trip
      expect((result!.a * 255).round(), 0xFF);
    });
  });

  group('colorFromHex / hexFromColor', () {
    test('round-trip a 6-digit RGB hex assumes opaque alpha', () {
      final color = colorFromHex('AABBCC');
      expect(color, isNotNull);
      expect(color, const Color(0xFFAABBCC));
      expect(hexFromColor(color!), 'AABBCCFF');
    });

    test('round-trip an 8-digit RRGGBBAA hex preserves alpha', () {
      final color = colorFromHex('11223380');
      expect(color, isNotNull);
      expect(color, const Color(0x80112233));
      expect(hexFromColor(color!), '11223380');
    });

    test('8-digit parse agrees with ThemePackCodec (RRGGBBAA order)', () {
      // The picker and the theme-pack document format must read the same
      // string as the same color; a picker that parsed AARRGGBB silently
      // swapped alpha and red on every hex copied out of a pack.
      const input = '#11223380';
      expect(colorFromHex(input), ThemePackCodec.tryParseColor(input));
    });

    test('emitted hex parses back through ThemePackCodec unchanged', () {
      const color = Color(0x80112233);
      expect(ThemePackCodec.tryParseColor(hexFromColor(color)), color);
    });

    test('accepts a leading # and is case-insensitive', () {
      expect(colorFromHex('#abcdef'), colorFromHex('ABCDEF'));
      expect(colorFromHex('#ABCDEF'), colorFromHex('abcdef'));
    });

    test('returns null on garbage input', () {
      expect(colorFromHex(''), isNull);
      expect(colorFromHex('xyz'), isNull);
      expect(colorFromHex('AABB'), isNull); // wrong length
      expect(colorFromHex('AABBCCDDEE'), isNull); // too long
      expect(colorFromHex('GGGGGG'), isNull); // non-hex char
    });

    test('trims whitespace', () {
      expect(colorFromHex('  AABBCC  '), isNotNull);
    });
  });
}
