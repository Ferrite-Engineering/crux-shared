// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/theme_registry.dart';
import 'package:flutter/material.dart' show Brightness, Color;

/// Returns the six built-in `CruxColorTheme` presets keyed by id.
///
/// - `crux-dark` — default. The suite's engineering-tool aesthetic.
/// - `crux-light` — light variant of the default.
/// - `solarized-dark` — Ethan Schoonover's Solarized Dark, with the
///   warm amber accent set.
/// - `high-contrast-dark` — WCAG AA, maximum contrast.
/// - `oscilloscope` — phosphor-green-on-black, single-hue accents.
/// - `oled-xr` — true-black, high-luminance palette tuned for
///   Micro-OLED XR / AR glasses (e.g. birdbath displays such as the
///   Viture Beast or Xreal One Pro). True `#000000` everywhere so OLED
///   pixels switch fully off (perfect blacks, no backlight bloom, lower
///   power); saturated multi-hue accents and tempered near-whites that
///   stay legible at the low angular resolution (~30 px/°) of current
///   XR optics, where thin desaturated lines and pure-white-on-black
///   fringe. Brand-neutral — not affiliated with any glasses maker.
///
/// **The presets carry only suite-wide `chrome` tokens.** Every
/// domain-specific token category — WaveCrux's waveform `canvas`, a
/// future NetCrux `schematic` — is contributed by the owning product
/// through `ThemeRegistry.registerPresetOverlay`, and is layered on
/// here. A product that registers no overlay gets presets with no
/// palette it cannot use; nothing throws and nothing is missing,
/// because absent tokens resolve through the registry to the
/// registered descriptor's brightness default.
///
/// The result is cached and recomputed only when the registry's
/// overlay set changes, so the common case is a map lookup.
Map<String, CruxColorTheme> builtinPresets() {
  final registry = ThemeRegistry.instance;
  final revision = registry.revision;
  final cached = _composedCache;
  if (cached != null && _composedCacheRevision == revision) return cached;

  final composed = <String, CruxColorTheme>{};
  for (final base in _basePresets) {
    composed[base.id] = _compose(base, registry);
  }
  final frozen = Map<String, CruxColorTheme>.unmodifiable(composed);
  _composedCache = frozen;
  _composedCacheRevision = revision;
  return frozen;
}

/// Convenience: returns the canonical default preset.
CruxColorTheme defaultBuiltinPreset() => builtinPresets()[cruxDarkPresetId]!;

/// Id of the suite default preset.
const String cruxDarkPresetId = 'crux-dark';

/// Id of the suite default light preset.
const String cruxLightPresetId = 'crux-light';

/// Preset ids retired in `0.3.0`, mapped to their replacement.
///
/// The `wavecrux-*` ids shipped through the public beta as the *shared*
/// default for every suite product, so they are persisted in the
/// settings of every beta user (`CoreSettings.activeThemeName`). They
/// are permanently accepted on the read path via [migratePresetId] and
/// [builtinPresetById]; only the written value changed.
const Map<String, String> legacyPresetIdAliases = <String, String>{
  'wavecrux-dark': cruxDarkPresetId,
  'wavecrux-light': cruxLightPresetId,
};

/// Migrates a persisted preset id to its current form.
///
/// Returns [id] unchanged when it is not a retired id — including for
/// ids this package has never heard of, which are user theme-pack ids
/// and must survive the round trip untouched.
///
/// Call this on every read of a persisted preset id (settings load,
/// session restore, pack activation) so beta users who saved
/// `wavecrux-light` do not silently fall back to the dark default.
String migratePresetId(String id) => legacyPresetIdAliases[id] ?? id;

/// Looks up a built-in preset by id, applying [migratePresetId] first.
///
/// Returns `null` when [id] names no built-in preset — the caller is
/// then looking at a user-installed theme pack id and should consult
/// `ThemePackService`.
CruxColorTheme? builtinPresetById(String id) =>
    builtinPresets()[migratePresetId(id)];

Map<String, CruxColorTheme>? _composedCache;
int _composedCacheRevision = -1;

/// Layers every registered `PresetTokenOverlay`'s contribution for
/// [base] on top of the base preset's own token table.
CruxColorTheme _compose(CruxColorTheme base, ThemeRegistry registry) {
  Map<String, Map<String, Color>>? merged;
  for (final overlay in registry.registeredPresetOverlays) {
    final contribution = overlay.tokensFor(base.id);
    if (contribution == null || contribution.isEmpty) continue;
    merged ??= <String, Map<String, Color>>{
      for (final entry in base.tokens.entries)
        entry.key: Map<String, Color>.from(entry.value),
    };
    final bucket = merged.putIfAbsent(
      overlay.categoryId,
      () => <String, Color>{},
    );
    // Base preset values win over overlay values, so a preset that
    // deliberately states a token keeps it.
    for (final tokenEntry in contribution.entries) {
      bucket.putIfAbsent(tokenEntry.key, () => tokenEntry.value);
    }
  }
  if (merged == null) return base;
  return base.copyWith(tokens: merged);
}

// ---------------------------------------------------------------------------
// Base preset bodies — brand-neutral chrome only.
//
// The status bar, splitter, document tab bar and active toolbar glyph tokens
// were declared here before any widget painted with them. Wiring them to
// their widgets must not recolor a preset, so each value below is the colour
// that surface already showed, and a token whose surface showed a colour of
// the host product's own Material theme (which differs per product and per
// contrast mode) is left out, so it keeps inheriting:
//
// - `statusBar.background`: the status bar showed `surfaceContainerHighest`,
//   which is `panel.header.background` here.
// - `statusBar.foreground`: its text showed `onSurface` at 75 % opacity,
//   which is `panel.header.foreground` at alpha 0xBF. Solarized Dark is the
//   one exception: that blend is 3.76:1 on its status bar, below WCAG AA's
//   4.5:1 for text, so it paints the declared `#93A1A1` opaque (5.61:1).
// - `tabBar.selected`: the active document tab showed
//   `surfaceContainerHighest`, again `panel.header.background`.
// - `toolbar.iconActive`, `splitter`, `splitter.hover`, `tabBar.background`
//   and `tabBar.label` are omitted: those surfaces showed the product's
//   `primary`, `outlineVariant`, nothing, and its body text colour.
//
// `builtin_presets_test.dart` pins every value, with the colour each preset
// declared before, so adopting a declared colour (as Solarized Dark's status
// bar text did) is a visible, deliberate change rather than a refactor.
// ---------------------------------------------------------------------------

final List<CruxColorTheme> _basePresets = <CruxColorTheme>[
  _cruxDark,
  _cruxLight,
  _solarizedDark,
  _highContrastDark,
  _oscilloscope,
  _oledXr,
];

final CruxColorTheme _cruxDark = CruxColorTheme(
  id: cruxDarkPresetId,
  displayName: 'Crux Dark',
  brightness: Brightness.dark,
  // chrome omitted — Material 3 defaults from the seed color.
  tokens: const <String, Map<String, Color>>{},
);

final CruxColorTheme _cruxLight = CruxColorTheme(
  id: cruxLightPresetId,
  displayName: 'Crux Light',
  brightness: Brightness.light,
  tokens: const <String, Map<String, Color>>{},
);

final CruxColorTheme _solarizedDark = CruxColorTheme(
  id: 'solarized-dark',
  displayName: 'Solarized Dark',
  brightness: Brightness.dark,
  tokens: const <String, Map<String, Color>>{
    'chrome': <String, Color>{
      'scaffold.background': Color(0xFF002B36),
      'panel.background': Color(0xFF073642),
      'panel.header.background': Color(0xFF002B36),
      'panel.header.foreground': Color(0xFF93A1A1),
      'toolbar.background': Color(0xFF002B36),
      'toolbar.icon': Color(0xFF839496),
      'statusBar.background': Color(0xFF002B36),
      'statusBar.foreground': Color(0xFF93A1A1),
      'tabBar.selected': Color(0xFF002B36),
    },
  },
);

final CruxColorTheme _highContrastDark = CruxColorTheme(
  id: 'high-contrast-dark',
  displayName: 'High Contrast Dark',
  brightness: Brightness.dark,
  tokens: const <String, Map<String, Color>>{},
);

final CruxColorTheme _oscilloscope = CruxColorTheme(
  id: 'oscilloscope',
  displayName: 'Oscilloscope',
  brightness: Brightness.dark,
  tokens: const <String, Map<String, Color>>{
    'chrome': <String, Color>{
      'scaffold.background': Color(0xFF000000),
      'panel.background': Color(0xFF020A02),
      'panel.header.background': Color(0xFF000000),
      'panel.header.foreground': Color(0xFF00FF41),
      'toolbar.background': Color(0xFF000000),
      'toolbar.icon': Color(0xFF00CC33),
      'statusBar.background': Color(0xFF000000),
      'statusBar.foreground': Color(0xBF00FF41),
      'tabBar.selected': Color(0xFF000000),
    },
  },
);

// Tuned for Micro-OLED XR / AR glasses (birdbath displays such as the
// Viture Beast / Xreal One Pro). Design rules, all aimed at the two
// things that hurt legibility through XR optics — backlight bloom that
// lifts the black floor, and low angular resolution that blurs
// thin/desaturated lines:
//   * True `#000000` for every surface so OLED pixels are fully off —
//     perfect blacks, no bloom halo around bright content, lower power.
//   * Saturated, well-separated accent hues (amber, cyan, green — no
//     fine blue lines, which fringe worst on birdbath optics).
//   * Near-white text tempered to `#F2F2F2` rather than pure white to
//     avoid the blue-channel bloom OLEDs show at high nits, while
//     neutral grays are lifted (`#9AA0A6`) for low-PPD legibility.
final CruxColorTheme _oledXr = CruxColorTheme(
  id: 'oled-xr',
  displayName: 'OLED XR',
  brightness: Brightness.dark,
  tokens: const <String, Map<String, Color>>{
    'chrome': <String, Color>{
      'scaffold.background': Color(0xFF000000),
      'panel.background': Color(0xFF050505),
      'panel.header.background': Color(0xFF000000),
      'panel.header.foreground': Color(0xFFF2F2F2),
      'toolbar.background': Color(0xFF000000),
      'toolbar.icon': Color(0xFF9AA0A6),
      'statusBar.background': Color(0xFF000000),
      'statusBar.foreground': Color(0xBFF2F2F2),
      'tabBar.selected': Color(0xFF000000),
    },
  },
);
