// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('builtinPresets', () {
    test('returns exactly six presets', () {
      final presets = builtinPresets();
      expect(presets.length, 6);
    });

    test('keys match preset ids', () {
      final presets = builtinPresets();
      expect(presets.keys.toSet(), {
        'crux-dark',
        'crux-light',
        'solarized-dark',
        'high-contrast-dark',
        'oscilloscope',
        'oled-xr',
      });
      for (final entry in presets.entries) {
        expect(entry.value.id, entry.key);
      }
    });

    test('every preset has a non-empty displayName', () {
      for (final preset in builtinPresets().values) {
        expect(preset.displayName, isNotEmpty);
      }
    });

    test('exactly one preset has light brightness', () {
      final light = builtinPresets().values.where(
        (p) => p.brightness == Brightness.light,
      );
      expect(light.length, 1);
      expect(light.single.id, 'crux-light');
    });

    test('five presets have dark brightness', () {
      final dark = builtinPresets().values.where(
        (p) => p.brightness == Brightness.dark,
      );
      expect(dark.length, 5);
    });

    // NOTE: the "every preset declares a canvas category / every required
    // canvas token" tests were removed when the requirement was inverted:
    // waveform tokens are WaveCrux's, contributed through
    // `ThemeRegistry.registerPresetOverlay`, and must NOT ship in the
    // shared presets. See preset_token_overlay_test.dart, which asserts
    // their absence and covers the replacement seam.

    test('the four branded presets register the chrome category', () {
      final presets = builtinPresets();
      expect(presets['solarized-dark']!.tokens.containsKey('chrome'), isTrue);
      expect(
        presets['high-contrast-dark']!.tokens.containsKey('chrome'),
        isTrue,
      );
      expect(presets['oscilloscope']!.tokens.containsKey('chrome'), isTrue);
      expect(presets['oled-xr']!.tokens.containsKey('chrome'), isTrue);
    });

    test('crux-dark omits the chrome category (M3 defaults)', () {
      final dark = builtinPresets()['crux-dark']!;
      expect(dark.tokens.containsKey('chrome'), isFalse);
    });

    test('round-trips through the codec', () {
      const codec = ThemePackCodec();
      for (final preset in builtinPresets().values) {
        final pack = ThemePack(
          id: preset.id,
          displayName: preset.displayName,
          brightness: preset.brightness,
          tokens: preset.tokens,
        );
        final decoded = codec.decode(codec.encode(pack));
        expect(
          decoded.id,
          preset.id,
          reason: 'id mismatch for ${preset.id}',
        );
        expect(
          decoded.brightness,
          preset.brightness,
          reason: 'brightness mismatch for ${preset.id}',
        );
        for (final categoryEntry in preset.tokens.entries) {
          for (final tokenEntry in categoryEntry.value.entries) {
            expect(
              decoded.color(categoryEntry.key, tokenEntry.key),
              tokenEntry.value,
              reason:
                  '${preset.id} '
                  '${categoryEntry.key}.${tokenEntry.key} round-trip',
            );
          }
        }
      }
    });

    test('defaultBuiltinPreset returns crux-dark', () {
      expect(defaultBuiltinPreset().id, 'crux-dark');
    });

    test('chrome signature values survived moving canvas tokens out', () {
      // Spot-check the suite-shared chrome values so an accidental edit
      // is caught. The canvas signature values these presets used to
      // carry moved to WaveCrux's canvas preset overlay; their guard
      // moves with them.
      final presets = builtinPresets();
      expect(
        presets['solarized-dark']!.color('chrome', 'scaffold.background'),
        const Color(0xFF002B36),
      );
      expect(
        presets['solarized-dark']!.color('chrome', 'panel.background'),
        const Color(0xFF073642),
      );
      // Oscilloscope's signature phosphor green.
      expect(
        presets['oscilloscope']!.color('chrome', 'panel.header.foreground'),
        const Color(0xFF00FF41),
      );
      // OLED XR: true black everywhere.
      expect(
        presets['oled-xr']!.color('chrome', 'scaffold.background'),
        const Color(0xFF000000),
      );
      expect(
        presets['oled-xr']!.color('chrome', 'toolbar.icon'),
        const Color(0xFF9AA0A6),
      );
    });
  });

  // Every chrome value each preset ships, spelled out rather than derived.
  // Changing a row is a visible change to a shipped preset, not a refactor.
  //
  // The branded presets take their chrome from their own palettes:
  // `toolbar.iconActive` and `splitter.hover` are the palette's primary, and
  // `splitter` is its minor-tick colour, raised (channels scaled, hue kept)
  // only as far as 3:1 against the panel and scaffold surfaces either side of
  // it. The trailing comment on each splitter row is the palette's tick colour
  // before raising. High Contrast Dark declares the full set: black surfaces,
  // white text and icons, yellow active.
  group('chrome values are pinned', () {
    const expected = <String, Map<String, Color?>>{
      'solarized-dark': {
        'scaffold.background': Color(0xFF002B36),
        'panel.background': Color(0xFF073642),
        'panel.header.background': Color(0xFF002B36),
        'panel.header.foreground': Color(0xFF93A1A1),
        'toolbar.background': Color(0xFF002B36),
        'toolbar.icon': Color(0xFF839496),
        'toolbar.iconActive': Color(0xFFB58900),
        'statusBar.background': Color(0xFF002B36),
        'statusBar.foreground': Color(0xFF93A1A1),
        'splitter': Color(0xFF657F87), // tick 0xFF586E75, 2.42:1
        'splitter.hover': Color(0xFFB58900),
        'tabBar.background': null,
        'tabBar.selected': Color(0xFF002B36),
        'tabBar.label': null,
      },
      'high-contrast-dark': {
        'scaffold.background': Color(0xFF000000),
        'panel.background': Color(0xFF000000),
        'panel.header.background': Color(0xFF000000),
        'panel.header.foreground': Color(0xFFFFFFFF),
        'toolbar.background': Color(0xFF000000),
        'toolbar.icon': Color(0xFFFFFFFF),
        'toolbar.iconActive': Color(0xFFFFFF00),
        'statusBar.background': Color(0xFF000000),
        'statusBar.foreground': Color(0xFFFFFFFF),
        'splitter': Color(0xFF666666), // tick 0xFF666666, already 3.66:1
        'splitter.hover': Color(0xFFFFFF00),
        'tabBar.background': Color(0xFF000000),
        'tabBar.selected': Color(0xFF000000),
        'tabBar.label': Color(0xFFFFFFFF),
      },
      'oscilloscope': {
        'scaffold.background': Color(0xFF000000),
        'panel.background': Color(0xFF020A02),
        'panel.header.background': Color(0xFF000000),
        'panel.header.foreground': Color(0xFF00FF41),
        'toolbar.background': Color(0xFF000000),
        'toolbar.icon': Color(0xFF00CC33),
        'toolbar.iconActive': Color(0xFF00FF41),
        'statusBar.background': Color(0xFF000000),
        'statusBar.foreground': Color(0xBF00FF41),
        'splitter': Color(0xFF256A25), // tick 0xFF1A4A1A, 1.95:1
        'splitter.hover': Color(0xFF00FF41),
        'tabBar.background': null,
        'tabBar.selected': Color(0xFF000000),
        'tabBar.label': null,
      },
      'oled-xr': {
        'scaffold.background': Color(0xFF000000),
        'panel.background': Color(0xFF050505),
        'panel.header.background': Color(0xFF000000),
        'panel.header.foreground': Color(0xFFF2F2F2),
        'toolbar.background': Color(0xFF000000),
        'toolbar.icon': Color(0xFF9AA0A6),
        'toolbar.iconActive': Color(0xFFFFD400),
        'statusBar.background': Color(0xFF000000),
        'statusBar.foreground': Color(0xBFF2F2F2),
        'splitter': Color(0xFF5C5C5C), // tick 0xFF5A5A5A, 2.96:1
        'splitter.hover': Color(0xFFFFD400),
        'tabBar.background': null,
        'tabBar.selected': Color(0xFF000000),
        'tabBar.label': null,
      },
      'crux-dark': {},
      'crux-light': {},
    };

    // The contrast each pinned pair measures, to two decimals, with its WCAG
    // 2.1 AA floor: 4.5:1 for text, 3:1 for icons and other UI components.
    // Translucent foregrounds are measured blended over their background.
    const contrast = <String, List<(String, String, double, double)>>{
      'solarized-dark': [
        ('panel.header.foreground', 'panel.header.background', 5.61, 4.5),
        ('statusBar.foreground', 'statusBar.background', 5.61, 4.5),
        ('toolbar.icon', 'toolbar.background', 4.75, 3),
        ('toolbar.iconActive', 'toolbar.background', 4.68, 3),
        ('splitter', 'panel.background', 3.06, 3),
        ('splitter', 'scaffold.background', 3.53, 3),
        ('splitter.hover', 'panel.background', 4.05, 3),
      ],
      'high-contrast-dark': [
        ('panel.header.foreground', 'panel.header.background', 21, 4.5),
        ('statusBar.foreground', 'statusBar.background', 21, 4.5),
        ('tabBar.label', 'tabBar.background', 21, 4.5),
        ('toolbar.icon', 'toolbar.background', 21, 3),
        ('toolbar.iconActive', 'toolbar.background', 19.56, 3),
        ('splitter', 'panel.background', 3.66, 3),
        ('splitter.hover', 'panel.background', 19.56, 3),
      ],
      'oscilloscope': [
        ('panel.header.foreground', 'panel.header.background', 15.38, 4.5),
        ('statusBar.foreground', 'statusBar.background', 8.50, 4.5),
        ('toolbar.icon', 'toolbar.background', 9.69, 3),
        ('toolbar.iconActive', 'toolbar.background', 15.38, 3),
        ('splitter', 'panel.background', 3.03, 3),
        ('splitter', 'scaffold.background', 3.17, 3),
        ('splitter.hover', 'panel.background', 14.69, 3),
      ],
      'oled-xr': [
        ('panel.header.foreground', 'panel.header.background', 18.76, 4.5),
        ('statusBar.foreground', 'statusBar.background', 10.27, 4.5),
        ('toolbar.icon', 'toolbar.background', 7.95, 3),
        ('toolbar.iconActive', 'toolbar.background', 14.67, 3),
        ('splitter', 'panel.background', 3.05, 3),
        ('splitter', 'scaffold.background', 3.14, 3),
        ('splitter.hover', 'panel.background', 14.24, 3),
      ],
    };

    test('the tables cover every preset', () {
      expect(expected.keys.toSet(), builtinPresets().keys.toSet());
      expect(
        contrast.keys.toSet(),
        builtinPresets().keys.toSet().difference({'crux-dark', 'crux-light'}),
      );
    });

    for (final presetEntry in expected.entries) {
      test(presetEntry.key, () {
        final preset = builtinPresets()[presetEntry.key]!;
        for (final descriptor in chromeTokens.tokens) {
          expect(
            preset.color(chromeCategoryId, descriptor.id)?.toARGB32(),
            presetEntry.value[descriptor.id]?.toARGB32(),
            reason: '${presetEntry.key} chrome.${descriptor.id}',
          );
        }
      });
    }

    for (final presetEntry in contrast.entries) {
      test('${presetEntry.key} contrast', () {
        final preset = builtinPresets()[presetEntry.key]!;
        for (final (fgToken, bgToken, ratio, floor) in presetEntry.value) {
          final bg = preset.color(chromeCategoryId, bgToken)!;
          final fg = Color.alphaBlend(
            preset.color(chromeCategoryId, fgToken)!,
            bg,
          );
          final measured = _contrastRatio(fg, bg);
          expect(
            measured,
            closeTo(ratio, 0.01),
            reason: '${presetEntry.key} $fgToken on $bgToken',
          );
          expect(
            measured,
            greaterThanOrEqualTo(floor),
            reason: '${presetEntry.key} $fgToken on $bgToken below $floor:1',
          );
        }
      });
    }
  });
}

/// WCAG 2.1 contrast ratio between two opaque colours.
double _contrastRatio(Color a, Color b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
