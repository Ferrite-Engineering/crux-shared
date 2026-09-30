// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter_test/flutter_test.dart';

/// Domain-specific token palettes are
/// contributed by the owning product through the registry seam, not
/// baked into the shared presets.
///
/// The defect these lock down: `builtinPresets()` used to ship 22
/// waveform tokens (`signal.x.fill`, `cursor.delta`, `marker.line`, …)
/// in all six presets, so NetCrux, LintCrux and SimCrux each carried —
/// and exposed in Settings → Appearance — a full waveform palette they
/// have no canvas to paint with.
void main() {
  setUp(ThemeRegistry.instance.resetForTesting);
  tearDown(ThemeRegistry.instance.resetForTesting);

  const waveformTokenKeys = <String>[
    'signal.x.fill',
    'signal.x.hatch',
    'signal.z.line',
    'signal.scalar.low',
    'signal.valueLabel',
    'cursor.primary',
    'cursor.secondary',
    'cursor.delta',
    'marker.line',
    'marker.flag',
    'marker.flagText',
    'ruler.background',
    'ruler.tick',
    'ruler.tickMajor',
    'ruler.label',
    'ruler.cursorTime',
  ];

  group('shared presets carry no product-specific palette', () {
    test('no built-in preset ships a canvas category by default', () {
      for (final preset in builtinPresets().values) {
        expect(
          preset.tokens.containsKey('canvas'),
          isFalse,
          reason:
              '${preset.id} must not ship a waveform canvas to products '
              'that have no waveform canvas',
        );
      }
    });

    test('no built-in preset ships any waveform token under any '
        'category', () {
      for (final preset in builtinPresets().values) {
        for (final bucket in preset.tokens.values) {
          for (final key in waveformTokenKeys) {
            expect(
              bucket.containsKey(key),
              isFalse,
              reason: '${preset.id} still ships waveform token "$key"',
            );
          }
        }
      }
    });

    test('presets still carry the suite-wide chrome vocabulary', () {
      // chrome IS shared: every product has a scaffold, panels, a
      // toolbar and a tab bar. That is the distinction the ruling drew.
      final solarized = builtinPresets()['solarized-dark']!;
      expect(solarized.color('chrome', 'scaffold.background'), isNotNull);
      expect(solarized.color('chrome', 'tabBar.selected'), isNotNull);
    });
  });

  group('a product contributes its palette through the registry', () {
    const canvasOverlay = PresetTokenOverlay(
      categoryId: 'canvas',
      byPresetId: {
        'crux-dark': {
          'background': Color(0xFF1A1A1A),
          'signal.x.fill': Color(0xFFFF2222),
        },
        'oscilloscope': {
          'background': Color(0xFF000000),
          'signal.x.fill': Color(0xFFFF3300),
        },
      },
    );

    test('registered overlay values appear in the composed presets', () {
      ThemeRegistry.instance.registerPresetOverlay(canvasOverlay);
      final presets = builtinPresets();
      expect(
        presets['crux-dark']!.color('canvas', 'signal.x.fill'),
        const Color(0xFFFF2222),
      );
      expect(
        presets['oscilloscope']!.color('canvas', 'background'),
        const Color(0xFF000000),
      );
    });

    test('presets the overlay does not mention are left alone', () {
      ThemeRegistry.instance.registerPresetOverlay(canvasOverlay);
      expect(
        builtinPresets()['solarized-dark']!.tokens.containsKey('canvas'),
        isFalse,
      );
    });

    test('an unregistered product gets no canvas at all', () {
      // This is the whole point: NetCrux registers no canvas overlay,
      // so NetCrux's presets have no waveform palette.
      for (final preset in builtinPresets().values) {
        expect(preset.tokens.containsKey('canvas'), isFalse);
      }
    });

    test('degrades gracefully — nothing throws without an overlay', () {
      expect(builtinPresets, returnsNormally);
      expect(defaultBuiltinPreset, returnsNormally);
      // And an absent token resolves through the registry to the
      // descriptor default, exactly as an incomplete theme pack does.
      ThemeRegistry.instance.registerCategory(
        const ThemeTokenCategory(
          id: 'canvas',
          displayName: 'Canvas',
          tokens: [
            ThemeTokenDescriptor(
              id: 'background',
              displayName: 'Background',
              lightDefault: Color(0xFFF5F5F5),
              darkDefault: Color(0xFF1A1A1A),
            ),
          ],
        ),
      );
      final resolved = ThemeRegistry.instance.resolve(
        builtinPresets()['crux-dark']!,
        'canvas',
        'background',
      );
      expect(resolved, const Color(0xFF1A1A1A));
    });

    test('multiple products can contribute disjoint categories', () {
      ThemeRegistry.instance
        ..registerPresetOverlay(canvasOverlay)
        ..registerPresetOverlay(
          const PresetTokenOverlay(
            categoryId: 'schematic',
            byPresetId: {
              'crux-dark': {'wire': Color(0xFF00FF00)},
            },
          ),
        );
      final dark = builtinPresets()['crux-dark']!;
      expect(dark.color('canvas', 'background'), const Color(0xFF1A1A1A));
      expect(dark.color('schematic', 'wire'), const Color(0xFF00FF00));
    });

    test('a preset value wins over an overlay value for the same '
        'token', () {
      // Shared presets stay authoritative for anything they state
      // explicitly, so a product cannot repaint suite chrome.
      ThemeRegistry.instance.registerPresetOverlay(
        const PresetTokenOverlay(
          categoryId: 'chrome',
          byPresetId: {
            'solarized-dark': {'scaffold.background': Color(0xFFFF00FF)},
          },
        ),
      );
      expect(
        builtinPresets()['solarized-dark']!.color(
          'chrome',
          'scaffold.background',
        ),
        const Color(0xFF002B36),
      );
    });

    test('composition is cached until the registry changes', () {
      ThemeRegistry.instance.registerPresetOverlay(canvasOverlay);
      final first = builtinPresets();
      expect(identical(builtinPresets(), first), isTrue);

      ThemeRegistry.instance.registerPresetOverlay(
        const PresetTokenOverlay(
          categoryId: 'other',
          byPresetId: {
            'crux-dark': {'x': Color(0xFF010101)},
          },
        ),
      );
      expect(identical(builtinPresets(), first), isFalse);
    });

    test('preset identity and brightness survive composition', () {
      ThemeRegistry.instance.registerPresetOverlay(canvasOverlay);
      final dark = builtinPresets()['crux-dark']!;
      expect(dark.id, 'crux-dark');
      expect(dark.displayName, 'Crux Dark');
      expect(dark.brightness, Brightness.dark);
    });
  });

  group('overlay registration is idempotent', () {
    const overlay = PresetTokenOverlay(
      categoryId: 'canvas',
      byPresetId: {
        'crux-dark': {'background': Color(0xFF111111)},
      },
    );

    test('re-registering an identical overlay is a no-op', () {
      ThemeRegistry.instance
        ..registerPresetOverlay(overlay)
        ..registerPresetOverlay(overlay);
      expect(ThemeRegistry.instance.registeredPresetOverlays.length, 1);
    });

    test('registering a conflicting overlay throws', () {
      ThemeRegistry.instance.registerPresetOverlay(overlay);
      expect(
        () => ThemeRegistry.instance.registerPresetOverlay(
          const PresetTokenOverlay(
            categoryId: 'canvas',
            byPresetId: {
              'crux-dark': {'background': Color(0xFF999999)},
            },
          ),
        ),
        throwsStateError,
      );
    });

    test('an empty category id is rejected', () {
      expect(
        () => ThemeRegistry.instance.registerPresetOverlay(
          const PresetTokenOverlay(categoryId: '', byPresetId: {}),
        ),
        throwsArgumentError,
      );
    });
  });
}
