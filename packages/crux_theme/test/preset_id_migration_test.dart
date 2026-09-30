// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the `wavecrux-*` → `crux-*` preset id rename.
///
/// These are the tests that stand between the rename and silently
/// resetting every beta user's saved theme. `CoreSettings` persists
/// `activeThemeName`, and every beta build wrote `wavecrux-dark` (or
/// `wavecrux-light`, for anyone who used the brightness toggle) into
/// shared preferences. Those strings are on disk on user machines
/// right now and cannot be rewritten retroactively, so the read path
/// must accept them forever.
void main() {
  setUp(ThemeRegistry.instance.resetForTesting);

  group('preset id migration', () {
    test('maps the retired wavecrux ids to their crux replacements', () {
      expect(migratePresetId('wavecrux-dark'), 'crux-dark');
      expect(migratePresetId('wavecrux-light'), 'crux-light');
    });

    test('leaves current ids untouched', () {
      for (final id in builtinPresets().keys) {
        expect(migratePresetId(id), id, reason: '$id must be stable');
      }
    });

    test('leaves unknown ids untouched so user pack ids survive', () {
      // A user theme pack id is arbitrary text this package has never
      // seen. Rewriting or dropping it would unactivate the user's
      // imported theme.
      expect(migratePresetId('my-custom-pack'), 'my-custom-pack');
      expect(migratePresetId(''), '');
    });

    test(
      'a beta user with wavecrux-dark persisted resolves to the new '
      'default preset rather than nothing',
      () {
        final restored = builtinPresetById('wavecrux-dark');
        expect(restored, isNotNull);
        expect(restored!.id, 'crux-dark');
        expect(restored.brightness, Brightness.dark);
      },
    );

    test(
      'a beta user with wavecrux-light persisted keeps a LIGHT theme',
      () {
        // The failure this guards is subtle and is the reason the
        // migration cannot be skipped: without it,
        // `presets[activeThemeName] ?? defaultPreset` silently returns
        // the DARK default, so every light-theme user's app flips to
        // dark on upgrade with no error anywhere.
        final restored = builtinPresetById('wavecrux-light');
        expect(restored, isNotNull);
        expect(restored!.id, 'crux-light');
        expect(restored.brightness, Brightness.light);
      },
    );

    test('builtinPresetById returns null for a genuinely unknown id', () {
      expect(builtinPresetById('not-a-preset'), isNull);
    });

    test('every legacy alias points at a real built-in preset', () {
      final presets = builtinPresets();
      for (final entry in legacyPresetIdAliases.entries) {
        expect(
          presets.containsKey(entry.value),
          isTrue,
          reason:
              'alias ${entry.key} -> ${entry.value} names no built-in preset',
        );
      }
    });

    test('the legacy ids are NOT themselves offered as presets', () {
      // They must resolve on read, but must never appear in the preset
      // picker — that would show the user two entries for one theme.
      final presets = builtinPresets();
      for (final legacy in legacyPresetIdAliases.keys) {
        expect(presets.containsKey(legacy), isFalse);
      }
    });
  });

  group('preset branding', () {
    test('no built-in preset id or display name mentions a product', () {
      for (final preset in builtinPresets().values) {
        expect(
          preset.id.toLowerCase(),
          isNot(contains('wavecrux')),
          reason: 'preset ids are shared across all four suite products',
        );
        expect(
          preset.displayName.toLowerCase(),
          isNot(contains('wavecrux')),
          reason: 'NetCrux users must not be shown "WaveCrux Dark"',
        );
      }
    });

    test('the suite default is crux-dark', () {
      expect(defaultBuiltinPreset().id, cruxDarkPresetId);
      expect(defaultBuiltinPreset().displayName, 'Crux Dark');
    });
  });
}
