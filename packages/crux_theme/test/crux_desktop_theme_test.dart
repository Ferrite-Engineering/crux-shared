// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:crux_theme/src/crux_desktop_theme.dart';
import 'package:crux_theme/src/crux_focus_ring_borders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every combination the four `MaterialApp` theme slots ask for.
const List<({Brightness brightness, bool highContrast})> _variants = [
  (brightness: Brightness.dark, highContrast: false),
  (brightness: Brightness.light, highContrast: false),
  (brightness: Brightness.dark, highContrast: true),
  (brightness: Brightness.light, highContrast: true),
];

ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: const Color(0xFF5C6BC0),
  brightness: brightness,
);

String _name(({Brightness brightness, bool highContrast}) v) =>
    '${v.brightness.name}${v.highContrast ? ', high contrast' : ''}';

Future<Size> _sizeOf(
  WidgetTester tester,
  ThemeData theme,
  Widget child, {
  Finder? finder,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: KeyedSubtree(key: key, child: child),
        ),
      ),
    ),
  );
  return tester.getSize(finder ?? find.byKey(key));
}

void main() {
  for (final v in _variants) {
    group('cruxDesktopTheme (${_name(v)})', () {
      final scheme = _scheme(v.brightness);
      final theme = cruxDesktopTheme(scheme, highContrast: v.highContrast);
      final ring = v.highContrast ? 2.5 : 1.5;

      test('carries the desktop tokens', () {
        final tokens = theme.extension<CruxDesktopTokens>();
        expect(tokens, isNotNull);
        expect(tokens!.controlHeight, 28);
        expect(tokens.denseControlHeight, 24);
        expect(tokens.rowHeight, 24);
        expect(tokens.twoLineRowHeight, 40);
        expect(tokens.controlRadius, 4);
        expect(tokens.menuRadius, 6);
        expect(tokens.groupRadius, 6);
        expect(tokens.dialogRadius, 8);
        expect(tokens.focusRingWidth, ring);
        expect(tokens.scrimOpacity, 0.18);
        expect(tokens.bodyFontSize, 13);
        expect(tokens.secondaryFontSize, 12);
        expect(tokens.titleFontSize, 14);
      });

      test('keeps the product colour scheme, with no surface tint', () {
        expect(theme.colorScheme.brightness, v.brightness);
        expect(theme.colorScheme.primary, scheme.primary);
        expect(theme.colorScheme.surface, scheme.surface);
        expect(theme.colorScheme.surfaceTint, Colors.transparent);
      });

      test('type: 13 body, 12 secondary, 14 semibold titles', () {
        final t = theme.textTheme;
        expect(t.bodyLarge?.fontSize, 13);
        expect(t.bodyMedium?.fontSize, 13);
        expect(t.bodySmall?.fontSize, 12);
        expect(t.labelLarge?.fontSize, 13);
        expect(t.titleMedium?.fontSize, 14);
        expect(t.titleMedium?.fontWeight, FontWeight.w600);
        expect(theme.dialogTheme.titleTextStyle?.fontSize, 14);
        expect(theme.dialogTheme.titleTextStyle?.fontWeight, FontWeight.w600);
      });

      test('uses the operating system UI font, not a bundled one', () {
        // No fontFamily anywhere: the platform typography supplies it.
        final stock = ThemeData(useMaterial3: true);
        for (final (name, style) in [
          ('bodyMedium', theme.textTheme.bodyMedium),
          ('bodySmall', theme.textTheme.bodySmall),
          ('labelLarge', theme.textTheme.labelLarge),
          ('titleMedium', theme.textTheme.titleMedium),
        ]) {
          expect(
            style?.fontFamily,
            stock.textTheme.bodyMedium?.fontFamily,
            reason: name,
          );
        }
        // The component styles carry the same platform face: a button label
        // and a dialog title read in the body's font.
        final face = stock.textTheme.bodyMedium?.fontFamily;
        expect(theme.dialogTheme.titleTextStyle?.fontFamily, face);
        expect(
          theme.filledButtonTheme.style!.textStyle!.resolve({})?.fontFamily,
          face,
        );
      });

      test('feedback is overlays, never ink', () {
        expect(theme.splashFactory, NoSplash.splashFactory);
        final style = theme.filledButtonTheme.style!;
        expect(style.splashFactory, NoSplash.splashFactory);
      });

      test('radius: 4 controls, 6 menus, toasts and cards, 8 dialogs', () {
        RoundedRectangleBorder rounded(ShapeBorder? s) =>
            s! as RoundedRectangleBorder;
        BorderRadius radius(ShapeBorder? s) =>
            rounded(s).borderRadius as BorderRadius;
        expect(radius(theme.dialogTheme.shape), BorderRadius.circular(8));
        expect(radius(theme.popupMenuTheme.shape), BorderRadius.circular(6));
        expect(radius(theme.snackBarTheme.shape), BorderRadius.circular(6));
        expect(
          radius(theme.menuTheme.style!.shape!.resolve({})),
          BorderRadius.circular(6),
        );
        // A card is a group box, one step above a control.
        expect(radius(theme.cardTheme.shape), BorderRadius.circular(6));
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.iconButtonTheme.style!,
          theme.segmentedButtonTheme.style!,
        ]) {
          expect(
            radius(style.shape!.resolve({})),
            BorderRadius.circular(4),
          );
        }
        final input = theme.inputDecorationTheme.enabledBorder!;
        expect(
          (input as OutlineInputBorder).borderRadius,
          BorderRadius.circular(4),
        );
      });

      test('elevation: a 1 px outlineVariant border on every surface', () {
        final dialog = theme.dialogTheme.shape! as RoundedRectangleBorder;
        expect(dialog.side.color, theme.colorScheme.outlineVariant);
        expect(dialog.side.width, 1);
        final card = theme.cardTheme.shape! as RoundedRectangleBorder;
        expect(card.side.color, theme.colorScheme.outlineVariant);
        expect(theme.cardTheme.elevation, 0);
        final menu = theme.popupMenuTheme.shape! as RoundedRectangleBorder;
        expect(menu.side.color, theme.colorScheme.outlineVariant);
        expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      });

      test('scrim: 18 % behind a blocking dialog', () {
        expect(
          theme.dialogTheme.barrierColor,
          Colors.black.withValues(alpha: 0.18),
        );
      });

      test('focus: a ${ring}px primary ring 2 px outside, as the owned '
          'controls draw it', () {
        const focused = {WidgetState.focused};
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.iconButtonTheme.style!,
        ]) {
          final shape = style.shape!.resolve(focused)! as CruxFocusRingShape;
          expect(shape.ring.color, theme.colorScheme.primary);
          expect(shape.ring.width, ring);
          expect(shape.gap, 2);
          expect(shape.borderRadius, BorderRadius.circular(4));
          // No ring at rest, and none on a disabled control.
          expect(style.shape!.resolve({}), isNot(isA<CruxFocusRingShape>()));
          expect(
            style.shape!.resolve({WidgetState.focused, WidgetState.disabled}),
            isNot(isA<CruxFocusRingShape>()),
          );
          // A button's own border does not change on focus.
          expect(
            style.side?.resolve(focused),
            style.side?.resolve(const <WidgetState>{}),
          );
        }
        final field =
            theme.inputDecorationTheme.focusedBorder!
                as CruxFocusRingInputBorder;
        expect(field.borderSide.color, theme.colorScheme.primary);
        expect(field.ring.width, ring);
        expect(field.ring.color, theme.colorScheme.primary);
        expect(field.gap, 2);
        final error =
            theme.inputDecorationTheme.focusedErrorBorder!
                as CruxFocusRingInputBorder;
        expect(error.ring.color, theme.colorScheme.error);
        expect(
          theme.dropdownMenuTheme.inputDecorationTheme!.focusedBorder,
          field,
        );
        final menuItem = theme.menuButtonTheme.style!.side!.resolve(focused)!;
        expect(menuItem.width, ring);
      });

      test('the ring shapes survive copyWith and the focus animation', () {
        final shape =
            theme.filledButtonTheme.style!.shape!.resolve({
                  WidgetState.focused,
                })!
                as CruxFocusRingShape;
        // ButtonStyleButton applies its side with copyWith.
        final sided = shape.copyWith(side: const BorderSide(color: Colors.red));
        expect(sided.ring, shape.ring);
        expect(sided.side.color, Colors.red);
        const rest = RoundedRectangleBorder();
        expect(ShapeBorder.lerp(rest, shape, 1), shape);
        expect(ShapeBorder.lerp(rest, shape, 0.6), shape);
        expect(
          ShapeBorder.lerp(shape, rest, 0.6),
          isNot(isA<CruxFocusRingShape>()),
        );
        final field =
            theme.inputDecorationTheme.focusedBorder!
                as CruxFocusRingInputBorder;
        expect(
          field.copyWith(borderSide: const BorderSide(width: 2)),
          isA<CruxFocusRingInputBorder>(),
        );
        expect(
          ShapeBorder.lerp(theme.inputDecorationTheme.enabledBorder, field, 1),
          field,
        );
      });

      test('the secondary button is neutral, not accent-coloured', () {
        final style = theme.outlinedButtonTheme.style!;
        expect(
          style.foregroundColor!.resolve({}),
          theme.colorScheme.onSurface,
        );
        expect(
          style.foregroundColor!.resolve({}),
          isNot(theme.colorScheme.primary),
        );
        expect(style.backgroundColor!.resolve({}), isNotNull);
        final rest = style.side!.resolve({})!;
        final hover = style.side!.resolve({WidgetState.hovered})!;
        expect(rest.width, 1);
        expect(
          rest.color,
          v.highContrast
              ? theme.colorScheme.outline
              : theme.colorScheme.outlineVariant,
        );
        expect(hover.color, isNot(rest.color));
      });

      test('a pressed accent button goes darker, never lighter', () {
        final style = theme.filledButtonTheme.style!;
        final primary = theme.colorScheme.primary;
        for (final state in [WidgetState.hovered, WidgetState.pressed]) {
          final overlay = style.overlayColor!.resolve({state})!;
          final face = Color.alphaBlend(overlay, primary);
          expect(
            face.computeLuminance(),
            lessThan(primary.computeLuminance()),
            reason: state.name,
          );
        }
      });

      test('menus and menu-like values are regular weight', () {
        expect(theme.dropdownMenuTheme.textStyle?.fontWeight, FontWeight.w400);
        expect(theme.popupMenuTheme.textStyle?.fontWeight, FontWeight.w400);
        expect(
          theme.popupMenuTheme.labelTextStyle!.resolve({})?.fontWeight,
          FontWeight.w400,
        );
        expect(
          theme.menuButtonTheme.style!.textStyle!.resolve({})?.fontWeight,
          FontWeight.w400,
        );
      });

      testWidgets('buttons are 28 px tall', (tester) async {
        for (final button in <Widget>[
          FilledButton(onPressed: () {}, child: const Text('OK')),
          OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
          TextButton(onPressed: () {}, child: const Text('More')),
        ]) {
          final size = await _sizeOf(tester, theme, button);
          expect(size.height, 28, reason: button.runtimeType.toString());
        }
      });

      testWidgets('an icon button is 28 px square', (tester) async {
        final size = await _sizeOf(
          tester,
          theme,
          IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
        );
        expect(size, const Size(28, 28));
      });

      testWidgets('a text field is 28 px tall', (tester) async {
        final size = await _sizeOf(
          tester,
          theme,
          const SizedBox(width: 200, child: TextField()),
          finder: find.byType(TextField),
        );
        expect(size.height, 28);
      });

      testWidgets('a search field with an icon stays 28 px tall', (
        tester,
      ) async {
        final size = await _sizeOf(
          tester,
          theme,
          const SizedBox(
            width: 200,
            child: TextField(
              decoration: InputDecoration(prefixIcon: Icon(Icons.search)),
            ),
          ),
          finder: find.byType(TextField),
        );
        expect(size.height, 28);
      });

      testWidgets('a segmented button is 26 px tall', (tester) async {
        final size = await _sizeOf(
          tester,
          theme,
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('One')),
              ButtonSegment(value: 1, label: Text('Two')),
            ],
            selected: const {0},
            onSelectionChanged: (_) {},
          ),
        );
        expect(size.height, 26);
      });

      testWidgets('a chip sits at the Chip widget floor, not a 32 px pill', (
        tester,
      ) async {
        // The 22 px token is below Chip's own 32 px floor less the density
        // adjustment, which no theme property moves (see cruxDesktopTheme).
        final size = await _sizeOf(
          tester,
          theme,
          const Chip(label: Text('Tag')),
          finder: find.byType(Chip),
        );
        expect(size.height, lessThanOrEqualTo(30));
      });

      testWidgets('list rows are 24 px single line and 40 px two-line', (
        tester,
      ) async {
        final one = await _sizeOf(
          tester,
          theme,
          const SizedBox(width: 300, child: ListTile(title: Text('Row'))),
          finder: find.byType(ListTile),
        );
        expect(one.height, 24);
        // A dense two-line ListTile sizes to its text; a two-line list holds
        // its rows at the token itself, and the text fits inside it.
        final two = await _sizeOf(
          tester,
          theme,
          SizedBox(
            width: 300,
            height: theme.extension<CruxDesktopTokens>()!.twoLineRowHeight,
            child: const ListTile(
              title: Text('Row'),
              subtitle: Text('Detail'),
            ),
          ),
        );
        expect(two.height, 40);
        expect(tester.takeException(), isNull);
        final natural = await _sizeOf(
          tester,
          theme,
          const SizedBox(
            width: 300,
            child: ListTile(title: Text('Row'), subtitle: Text('Detail')),
          ),
          finder: find.byType(ListTile),
        );
        expect(natural.height, lessThanOrEqualTo(40));
      });

      testWidgets('a checkbox is shrink-wrapped, not a 48 px target', (
        tester,
      ) async {
        final size = await _sizeOf(
          tester,
          theme,
          Checkbox(value: true, onChanged: (_) {}),
          finder: find.byType(Checkbox),
        );
        expect(size.height, lessThanOrEqualTo(24));
      });
    });
  }

  group('cruxThemeForDevice', () {
    final scheme = _scheme(Brightness.dark);
    final mobile = ThemeData(useMaterial3: true, colorScheme: scheme);

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('${platform.name} gets the desktop layer', () {
        final theme = cruxThemeForDevice(
          colorScheme: scheme,
          highContrast: false,
          mobile: () => mobile,
          platform: platform,
          isWeb: false,
        );
        expect(theme.extension<CruxDesktopTokens>(), isNotNull);
      });
    }

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      test('${platform.name} keeps the product phone and tablet theme', () {
        final theme = cruxThemeForDevice(
          colorScheme: scheme,
          highContrast: false,
          mobile: () => mobile,
          platform: platform,
          isWeb: false,
        );
        expect(identical(theme, mobile), isTrue);
        expect(theme.extension<CruxDesktopTokens>(), isNull);
      });
    }

    test('the web gets the desktop layer whatever the platform', () {
      final theme = cruxThemeForDevice(
        colorScheme: scheme,
        highContrast: false,
        mobile: () => mobile,
        platform: TargetPlatform.iOS,
        isWeb: true,
      );
      expect(theme.extension<CruxDesktopTokens>(), isNotNull);
    });

    test('high contrast reaches the tokens', () {
      final theme = cruxThemeForDevice(
        colorScheme: scheme,
        highContrast: true,
        mobile: () => mobile,
        platform: TargetPlatform.linux,
        isWeb: false,
      );
      expect(theme.extension<CruxDesktopTokens>()!.focusRingWidth, 2.5);
    });
  });

  group('theme packs on the desktop theme', () {
    test('chrome tokens still override, and the desktop tokens survive', () {
      final base = cruxDesktopTheme(
        _scheme(Brightness.dark),
        highContrast: false,
      );
      const scaffold = Color(0xFF102030);
      const panel = Color(0xFF203040);
      const toolbar = Color(0xFF304050);
      final pack = CruxColorTheme(
        id: 'test-pack',
        displayName: 'Test pack',
        brightness: Brightness.dark,
        tokens: const {
          chromeCategoryId: {
            ChromeTokens.scaffoldBackground: scaffold,
            ChromeTokens.panelBackground: panel,
            ChromeTokens.toolbarBackground: toolbar,
            ChromeTokens.splitter: Color(0xFF405060),
          },
        },
      );
      final themed = applyChromeTokens(base, CruxThemeExtension(theme: pack));

      expect(themed.scaffoldBackgroundColor, scaffold);
      expect(themed.colorScheme.surface, panel);
      expect(themed.appBarTheme.backgroundColor, toolbar);
      expect(themed.cardTheme.color, panel);
      expect(
        themed.extension<CruxChromeColors>()?.splitter,
        const Color(0xFF405060),
      );
      // The component themes and the desktop tokens are untouched.
      expect(themed.extension<CruxDesktopTokens>(), isNotNull);
      expect(themed.dialogTheme, base.dialogTheme);
      expect(themed.filledButtonTheme, base.filledButtonTheme);
    });
  });
}
