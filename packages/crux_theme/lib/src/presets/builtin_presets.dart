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
/// - `high-contrast-dark` — black surfaces, white text and icons, yellow
///   for everything active.
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
// Each branded preset's chrome comes from its own designed palette, the same
// one its waveform canvas overlay is drawn from:
//
// - `toolbar.iconActive` and `splitter.hover` take the palette's primary
//   accent, so a toggled toolbar glyph and a grabbed resizer light up in the
//   preset's colour rather than the host product's Material `primary`.
// - `splitter` takes the palette's minor-tick colour, raised by scaling its
//   channels (hue kept) only as far as WCAG 2.1's 3:1 for user interface
//   components against both `panel.background` and `scaffold.background`.
//   Solarized Dark's #586E75 becomes #657F87, Oscilloscope's #1A4A1A becomes
//   #256A25 and OLED XR's #5A5A5A becomes #5C5C5C; High Contrast Dark's
//   #666666 already clears it.
// - `statusBar.background`, `statusBar.foreground` and `tabBar.selected` keep
//   the values the presets painted before their widgets read them (the status
//   bar showed `panel.header.background` behind `panel.header.foreground` at
//   75 %, opaque on Solarized Dark for AA; the active tab showed
//   `panel.header.background`).
// - `tabBar.background` and `tabBar.label` stay unset on the three accent
//   presets, so the strip keeps no fill and titles keep the body text colour.
//
// High Contrast Dark declares the full set: black surfaces, white text and
// icons, and yellow (#FFFF00) for everything active.
//
// `builtin_presets_test.dart` pins every value and its contrast, so a change
// here is a visible, deliberate change to a shipped preset.
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
      'toolbar.iconActive': Color(0xFFB58900),
      'statusBar.background': Color(0xFF002B36),
      'statusBar.foreground': Color(0xFF93A1A1),
      'splitter': Color(0xFF657F87),
      'splitter.hover': Color(0xFFB58900),
      'tabBar.selected': Color(0xFF002B36),
    },
  },
);

final CruxColorTheme _highContrastDark = CruxColorTheme(
  id: 'high-contrast-dark',
  displayName: 'High Contrast Dark',
  brightness: Brightness.dark,
  tokens: const <String, Map<String, Color>>{
    'chrome': <String, Color>{
      'scaffold.background': Color(0xFF000000),
      'panel.background': Color(0xFF000000),
      'panel.header.background': Color(0xFF000000),
      'panel.header.foreground': Color(0xFFFFFFFF),
      'toolbar.background': Color(0xFF000000),
      'toolbar.icon': Color(0xFFFFFFFF),
      'toolbar.iconActive': Color(0xFFFFFF00),
      'statusBar.background': Color(0xFF000000),
      'statusBar.foreground': Color(0xFFFFFFFF),
      'splitter': Color(0xFF666666),
      'splitter.hover': Color(0xFFFFFF00),
      'tabBar.background': Color(0xFF000000),
      'tabBar.selected': Color(0xFF000000),
      'tabBar.label': Color(0xFFFFFFFF),
    },
  },
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
      'toolbar.iconActive': Color(0xFF00FF41),
      'statusBar.background': Color(0xFF000000),
      'statusBar.foreground': Color(0xBF00FF41),
      'splitter': Color(0xFF256A25),
      'splitter.hover': Color(0xFF00FF41),
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
      'toolbar.iconActive': Color(0xFFFFD400),
      'statusBar.background': Color(0xFF000000),
      'statusBar.foreground': Color(0xBFF2F2F2),
      'splitter': Color(0xFF5C5C5C),
      'splitter.hover': Color(0xFFFFD400),
      'tabBar.selected': Color(0xFF000000),
    },
  },
);
