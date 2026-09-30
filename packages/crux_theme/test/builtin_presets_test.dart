// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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

    test('solarized, oscilloscope, oled-xr register the chrome category', () {
      final presets = builtinPresets();
      expect(presets['solarized-dark']!.tokens.containsKey('chrome'), isTrue);
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

  // The status bar, splitter, document tab bar and active toolbar glyph tokens
  // were declared by three presets long before any widget painted with them.
  // Wiring them must not recolor a preset, so each declared value was pinned
  // to the colour that surface already showed, and a token whose surface
  // showed the host product's own Material colour was dropped so it keeps
  // inheriting. The table is the canonical expectation, spelled out rather
  // than derived; the trailing comment on each row is the value the preset
  // declared before, which is what a designer would adopt. Changing a row is
  // a visible change to a shipped preset, not a refactor.
  //
  // One row has been changed that way. Solarized Dark's status bar text was
  // pinned to what it painted, 0xBF93A1A1: #93A1A1 at 75 % over #002B36 is
  // 3.76:1, below WCAG AA's 4.5:1 for text. It now adopts the declared opaque
  // #93A1A1, 5.61:1, so that text is brighter than it used to be.
  group('chrome widget tokens are pinned to what the presets painted', () {
    const expected = <String, Map<String, Color?>>{
      'solarized-dark': {
        'toolbar.iconActive': null, // declared 0xFF93A1A1
        'statusBar.background': Color(0xFF002B36), // declared 0xFF073642
        // Adopted for AA; it painted 0xBF93A1A1 before.
        'statusBar.foreground': Color(0xFF93A1A1), // declared 0xFF93A1A1
        'splitter': null, // declared 0xFF0A4652
        'splitter.hover': null, // declared 0xFF268BD2
        'tabBar.background': null, // declared 0xFF073642
        'tabBar.selected': Color(0xFF002B36), // declared 0xFF268BD2
        'tabBar.label': null, // declared 0xFF93A1A1
      },
      'oscilloscope': {
        'toolbar.iconActive': null, // declared 0xFF00FF41
        'statusBar.background': Color(0xFF000000), // unchanged
        'statusBar.foreground': Color(0xBF00FF41), // declared 0xFF00CC33
        'splitter': null, // declared 0xFF0F2A0F
        'splitter.hover': null, // declared 0xFF00FF41
        'tabBar.background': null, // declared 0xFF020A02
        'tabBar.selected': Color(0xFF000000), // declared 0xFF00FF41
        'tabBar.label': null, // declared 0xFF00CC33
      },
      'oled-xr': {
        'toolbar.iconActive': null, // declared 0xFFFFD400
        'statusBar.background': Color(0xFF000000), // unchanged
        'statusBar.foreground': Color(0xBFF2F2F2), // declared 0xFFCFCFCF
        'splitter': null, // declared 0xFF1C1C1C
        'splitter.hover': null, // declared 0xFF00E5FF
        'tabBar.background': null, // declared 0xFF050505
        'tabBar.selected': Color(0xFF000000), // declared 0xFFFFD400
        'tabBar.label': null, // declared 0xFF9AA0A6
      },
      'crux-dark': {},
      'crux-light': {},
      'high-contrast-dark': {},
    };

    test('the table covers every preset', () {
      expect(expected.keys.toSet(), builtinPresets().keys.toSet());
    });

    for (final presetEntry in expected.entries) {
      test(presetEntry.key, () {
        final preset = builtinPresets()[presetEntry.key]!;
        for (final token in const [
          'toolbar.iconActive',
          'statusBar.background',
          'statusBar.foreground',
          'splitter',
          'splitter.hover',
          'tabBar.background',
          'tabBar.selected',
          'tabBar.label',
        ]) {
          expect(
            preset.color(chromeCategoryId, token)?.toARGB32(),
            presetEntry.value[token]?.toARGB32(),
            reason: '${presetEntry.key} chrome.$token',
          );
        }
      });
    }
  });
}
