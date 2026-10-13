// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Every built-in preset must look exactly as it did before the status bar,
// splitter, document tab bar and active toolbar glyph tokens reached their
// widgets.
//
// Before, each of those widgets painted from the Material theme the product
// built with `applyChromeTokens`: the status bar `surfaceContainerHighest`
// behind `onSurface` at 75 %, the resizers `outlineVariant` and `primary`, the
// active document tab `surfaceContainerHighest` under `bodyMedium` titles on a
// transparent strip, and a toggled toolbar glyph `primary`. Now each widget
// paints the resolved token when there is one and that same colour when there
// is not (the widget packages' own tests prove that half). So an unedited
// preset is unchanged exactly when every token it resolves is either unset or
// equal to the colour the old computation gives.
//
// The products build that Material theme from their own light, dark and
// high-contrast bases, which differ from each other. The pinned preset values
// are copies of tokens `applyChromeTokens` itself writes into the scheme, so
// the check holds for any base; it runs against several unrelated ones to
// prove that rather than assume it.
//
// Text reaches the engine as 32-bit ARGB, so foreground colours are compared
// that way (a pinned 0xBF alpha and `withValues(alpha: 0.75)` encode to the
// same byte). Surfaces are painted from the colour's floats, so those must be
// the identical colour.
//
// A deliberate departure is listed in `_changedOnPurpose` with the colour it
// paints now, and is checked against that instead:
//
// - Solarized Dark's status bar text, which painted 3.76:1 against WCAG AA's
//   4.5:1 and now paints its declared opaque #93A1A1 (5.61:1).
// - The branded presets' active toolbar glyph, splitter and splitter hover,
//   which now come from each preset's own palette instead of the product's
//   `primary` and `outlineVariant`.
// - High Contrast Dark, which used to declare nothing and now declares the
//   whole chrome set: black surfaces, white text and icons, yellow active.
//
// `builtin_presets_test.dart` pins those values and their contrast.
const _changedOnPurpose = <(String, String), Color>{
  ('solarized-dark', 'statusBar.foreground'): Color(0xFF93A1A1),
  ('solarized-dark', 'toolbar.iconActive'): Color(0xFFB58900),
  ('solarized-dark', 'splitter'): Color(0xFF657F87),
  ('solarized-dark', 'splitter.hover'): Color(0xFFB58900),
  ('oscilloscope', 'toolbar.iconActive'): Color(0xFF00FF41),
  ('oscilloscope', 'splitter'): Color(0xFF256A25),
  ('oscilloscope', 'splitter.hover'): Color(0xFF00FF41),
  ('oled-xr', 'toolbar.iconActive'): Color(0xFFFFD400),
  ('oled-xr', 'splitter'): Color(0xFF5C5C5C),
  ('oled-xr', 'splitter.hover'): Color(0xFFFFD400),
  ('high-contrast-dark', 'toolbar.iconActive'): Color(0xFFFFFF00),
  ('high-contrast-dark', 'statusBar.foreground'): Color(0xFFFFFFFF),
  ('high-contrast-dark', 'splitter'): Color(0xFF666666),
  ('high-contrast-dark', 'splitter.hover'): Color(0xFFFFFF00),
  ('high-contrast-dark', 'tabBar.background'): Color(0xFF000000),
  ('high-contrast-dark', 'tabBar.label'): Color(0xFFFFFFFF),
};

final _bases = <String, ThemeData>{
  'seeded dark': ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4650C8),
      brightness: Brightness.dark,
    ),
  ),
  'seeded light': ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4650C8)),
  ),
  'high-contrast dark': ThemeData(
    colorScheme: const ColorScheme.highContrastDark(),
  ),
  'high-contrast light': ThemeData(
    colorScheme: const ColorScheme.highContrastLight(),
  ),
  'unrelated dark': ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFE0A000),
      brightness: Brightness.dark,
    ),
    textTheme: const TextTheme(bodyMedium: TextStyle(color: Color(0xFF77AA33))),
  ),
  'Material default': ThemeData(),
};

void main() {
  for (final preset in builtinPresets().values) {
    group(preset.id, () {
      for (final base in _bases.entries) {
        test('paints what it always painted over a ${base.key} base', () {
          final chrome = CruxThemeExtension(theme: preset);
          final theme = applyChromeTokens(
            base.value.copyWith(extensions: [chrome]),
            chrome,
          );
          final scheme = theme.colorScheme;
          final c = theme.extension<CruxChromeColors>()!;

          void surface(String token, Color? resolved, Color? before) {
            final now = _changedOnPurpose[(preset.id, token)];
            if (now != null) {
              expect(
                resolved?.toARGB32(),
                now.toARGB32(),
                reason: '$token over ${base.key}',
              );
              return;
            }
            if (resolved == null) return;
            expect(resolved, before, reason: '$token over ${base.key}');
          }

          void text(String token, Color? resolved, Color? before) {
            final now = _changedOnPurpose[(preset.id, token)];
            if (resolved == null && now == null) return;
            expect(
              resolved?.toARGB32(),
              (now ?? before)?.toARGB32(),
              reason: '$token over ${base.key}',
            );
          }

          surface(
            'statusBar.background',
            c.statusBarBackground,
            scheme.surfaceContainerHighest,
          );
          text(
            'statusBar.foreground',
            c.statusBarForeground,
            scheme.onSurface.withValues(alpha: 0.75),
          );
          surface('splitter', c.splitter, scheme.outlineVariant);
          surface('splitter.hover', c.splitterHover, scheme.primary);
          surface(
            'tabBar.selected',
            c.tabBarSelected,
            scheme.surfaceContainerHighest,
          );
          text(
            'tabBar.label',
            c.tabBarLabel,
            theme.textTheme.bodyMedium?.color,
          );
          surface('toolbar.iconActive', c.toolbarIconActive, scheme.primary);
          // The strip had no fill at all, so any value would add one.
          surface('tabBar.background', c.tabBarBackground, null);
        });
      }
    });
  }
}
