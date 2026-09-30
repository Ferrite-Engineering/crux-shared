// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_chrome_colors.dart';
import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/crux_theme_extension.dart';
import 'package:crux_theme/src/theme_registry.dart';
import 'package:crux_theme/src/theme_token_category.dart';
import 'package:flutter/material.dart';

/// The conventional `chrome` token category id used by suite presets.
///
/// Presets that customise chrome (e.g. `solarized-dark`, `oscilloscope`)
/// store their overrides under this category. Apps must register
/// matching `ThemeTokenDescriptor`s through their own `ThemeRegistry`
/// adapter so unknown tokens resolve to a sensible fallback rather than
/// the transparent sentinel.
const String chromeCategoryId = 'chrome';

/// Conventional chrome token ids consumed by [applyChromeTokens]. Apps
/// may declare additional tokens in their own catalog; only these reach a
/// widget through [applyChromeTokens].
///
/// The first six become Material `ColorScheme` / `AppBarTheme` / `CardTheme`
/// overrides. Material has no slot for the other eight, so they become a
/// [CruxChromeColors] extension that the shared chrome widgets read.
abstract final class ChromeTokens {
  /// Background colour of the root `Scaffold`.
  static const String scaffoldBackground = 'scaffold.background';

  /// Background colour of side and bottom panel surfaces.
  static const String panelBackground = 'panel.background';

  /// Background colour of panel header strips.
  static const String panelHeaderBackground = 'panel.header.background';

  /// Foreground (title + icon) colour of panel header strips.
  static const String panelHeaderForeground = 'panel.header.foreground';

  /// Background colour of the primary `AppBar` / toolbar.
  static const String toolbarBackground = 'toolbar.background';

  /// Default colour of toolbar icons in their resting state.
  static const String toolbarIcon = 'toolbar.icon';

  /// Glyph tint of a toggled-on toolbar button
  /// ([CruxChromeColors.toolbarIconActive]).
  static const String toolbarIconActive = 'toolbar.iconActive';

  /// Status bar surface ([CruxChromeColors.statusBarBackground]).
  static const String statusBarBackground = 'statusBar.background';

  /// Status bar text ([CruxChromeColors.statusBarForeground]).
  static const String statusBarForeground = 'statusBar.foreground';

  /// Pane resizer at rest ([CruxChromeColors.splitter]).
  static const String splitter = 'splitter';

  /// Pane resizer while hovered, dragged or focused
  /// ([CruxChromeColors.splitterHover]).
  static const String splitterHover = 'splitter.hover';

  /// Document tab strip ([CruxChromeColors.tabBarBackground]).
  static const String tabBarBackground = 'tabBar.background';

  /// Active document tab ([CruxChromeColors.tabBarSelected]).
  static const String tabBarSelected = 'tabBar.selected';

  /// Document tab titles ([CruxChromeColors.tabBarLabel]).
  static const String tabBarLabel = 'tabBar.label';
}

/// Reads a chrome token, returning `null` when the active theme omits
/// it or stores a transparent sentinel.
Color? _chromeToken(CruxThemeExtension chrome, String tokenId) {
  final c = chrome.theme.color(chromeCategoryId, tokenId);
  if (c == null) return null;
  final alpha = (c.a * 255.0).round().clamp(0, 255);
  if (alpha == 0) return null;
  return c;
}

/// Returns a copy of [base] with chrome-token overrides from [chrome]
/// applied. Tokens absent from the active preset fall through to [base]
/// unchanged, so default-Material presets (e.g. `crux-dark`,
/// `crux-light`) keep their tuned defaults while branded presets
/// (e.g. `solarized-dark`, `oscilloscope`) recolor the scaffold,
/// app bar, card surfaces, and panel surfaces.
///
/// The result always carries a [CruxChromeColors] extension holding the
/// status bar, splitter, document tab bar and active toolbar glyph tokens,
/// which the shared chrome widgets read. A token the theme leaves unset
/// keeps the value of a [CruxChromeColors] already on [base], if any, and
/// otherwise stays null so the widget keeps its own default.
///
/// Wire into a per-product `MaterialApp` like:
///
/// ```dart
/// final cruxColorTheme = ref.watch(cruxColorThemeProvider);
/// final chromeExt = CruxThemeExtension(theme: cruxColorTheme);
/// final themeMode = cruxColorTheme.brightness == Brightness.light
///     ? ThemeMode.light
///     : ThemeMode.dark;
/// return MaterialApp(
///   themeMode: themeMode,
///   theme: applyChromeTokens(MyTheme.light, chromeExt),
///   darkTheme: applyChromeTokens(MyTheme.dark, chromeExt),
/// );
/// ```
ThemeData applyChromeTokens(ThemeData base, CruxThemeExtension chrome) {
  final scaffoldBg = _chromeToken(chrome, ChromeTokens.scaffoldBackground);
  final panelBg = _chromeToken(chrome, ChromeTokens.panelBackground);
  final panelHeaderBg = _chromeToken(
    chrome,
    ChromeTokens.panelHeaderBackground,
  );
  final panelHeaderFg = _chromeToken(
    chrome,
    ChromeTokens.panelHeaderForeground,
  );
  final toolbarBg = _chromeToken(chrome, ChromeTokens.toolbarBackground);
  final toolbarIcon = _chromeToken(chrome, ChromeTokens.toolbarIcon);

  ColorScheme? overriddenScheme;
  if (scaffoldBg != null || panelBg != null || panelHeaderBg != null) {
    overriddenScheme = base.colorScheme.copyWith(
      surface: panelBg ?? scaffoldBg ?? base.colorScheme.surface,
      surfaceContainerHighest:
          panelHeaderBg ?? panelBg ?? base.colorScheme.surfaceContainerHighest,
      onSurface: panelHeaderFg ?? base.colorScheme.onSurface,
    );
  }

  final inherited = base.extension<CruxChromeColors>();
  Color? widgetToken(String tokenId, Color? fallback) =>
      _chromeToken(chrome, tokenId) ?? fallback;
  final chromeColors = CruxChromeColors(
    toolbarIconActive: widgetToken(
      ChromeTokens.toolbarIconActive,
      inherited?.toolbarIconActive,
    ),
    statusBarBackground: widgetToken(
      ChromeTokens.statusBarBackground,
      inherited?.statusBarBackground,
    ),
    statusBarForeground: widgetToken(
      ChromeTokens.statusBarForeground,
      inherited?.statusBarForeground,
    ),
    splitter: widgetToken(ChromeTokens.splitter, inherited?.splitter),
    splitterHover: widgetToken(
      ChromeTokens.splitterHover,
      inherited?.splitterHover,
    ),
    tabBarBackground: widgetToken(
      ChromeTokens.tabBarBackground,
      inherited?.tabBarBackground,
    ),
    tabBarSelected: widgetToken(
      ChromeTokens.tabBarSelected,
      inherited?.tabBarSelected,
    ),
    tabBarLabel: widgetToken(ChromeTokens.tabBarLabel, inherited?.tabBarLabel),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scaffoldBg ?? base.scaffoldBackgroundColor,
    colorScheme: overriddenScheme ?? base.colorScheme,
    appBarTheme: toolbarBg != null
        ? base.appBarTheme.copyWith(
            backgroundColor: toolbarBg,
            foregroundColor: toolbarIcon ?? base.appBarTheme.foregroundColor,
          )
        : base.appBarTheme,
    cardTheme: panelBg != null
        ? base.cardTheme.copyWith(color: panelBg)
        : base.cardTheme,
    extensions: [
      ...base.extensions.values.where((e) => e is! CruxChromeColors),
      chromeColors,
    ],
  );
}

/// Convenience: derives the Material [ThemeMode] from the active
/// preset's brightness so a `MaterialApp` driven by [theme] flips
/// between light/dark chrome as the user picks presets.
ThemeMode themeModeFromBrightness(CruxColorTheme theme) =>
    theme.brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark;

/// Shared `chrome` token catalog used by every suite product
/// (WaveCrux and future Crux products). Each app registers this
/// category with [ThemeRegistry] at bootstrap so Settings → Appearance
/// surfaces a uniform chrome-tweak UI across the suite.
///
/// Every token here reaches a painted surface through [applyChromeTokens]
/// (see [ChromeTokens]); a token nothing paints with does not belong here,
/// because the editor would offer a setting that silently does nothing.
///
/// Token defaults are intentionally fully-transparent sentinels — a
/// theme pack that omits a chrome token resolves to a transparent
/// color in the registry, and [applyChromeTokens] interprets that
/// transparency as "use the base ThemeData's value", preserving the
/// "no override → Material default" semantics.
const ThemeTokenCategory chromeTokens = ThemeTokenCategory(
  id: chromeCategoryId,
  displayName: 'Application chrome',
  tokens: [
    ThemeTokenDescriptor(
      id: ChromeTokens.scaffoldBackground,
      displayName: 'Scaffold background',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.panelBackground,
      displayName: 'Panel background',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.panelHeaderBackground,
      displayName: 'Panel header background',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.panelHeaderForeground,
      displayName: 'Panel header foreground',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.toolbarBackground,
      displayName: 'Toolbar background',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.toolbarIcon,
      displayName: 'Toolbar icon',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.toolbarIconActive,
      displayName: 'Toolbar icon (active)',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.statusBarBackground,
      displayName: 'Status bar background',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.statusBarForeground,
      displayName: 'Status bar foreground',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.splitter,
      displayName: 'Splitter',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.splitterHover,
      displayName: 'Splitter (hover)',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.tabBarBackground,
      displayName: 'Tab bar background',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.tabBarSelected,
      displayName: 'Tab bar (selected)',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: ChromeTokens.tabBarLabel,
      displayName: 'Tab bar label',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
  ],
);

/// Idempotently registers the shared [chromeTokens] catalog with
/// [ThemeRegistry]. Each app calls this once from its bootstrap so
/// per-token override editors and `.crux-theme.json` pack imports
/// recognise the chrome token ids without each adopter copying a
/// catalog.
void registerCruxThemeChromeTokens() {
  final registry = ThemeRegistry.instance;
  if (!registry.hasCategory(chromeTokens.id)) {
    registry.registerCategory(chromeTokens);
  }
}
