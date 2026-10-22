// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite named-token color theming infrastructure for the EDACrux
/// suite.
///
/// **Foundation (`0.1.0`):** the `CruxColorTheme` immutable value type
/// with category-keyed token storage, the `ThemeTokenCategory` /
/// `ThemeTokenDescriptor` schema each product registers at startup, the
/// `ThemePack` JSON-pack representation with strict-schema
/// `ThemePackCodec` encode/decode and `ThemePackService`
/// install/list/uninstall file-system ops, six built-in presets via
/// `builtinPresets()`, the runtime `ThemeRegistry` consumers fill with
/// their token categories, the Riverpod-backed `cruxColorThemeProvider`,
/// and the Flutter `CruxThemeExtension` for `ThemeData.extensions`
/// integration.
///
/// **Settings → Appearance UI (`0.2.0`):** caller-supplied L10N via
/// `ThemeAppearanceStrings` + the const `ThemeAppearanceStringsEn`
/// default, a built-in `ColorPickerDialog` (HSV sliders + hex input +
/// RGB read-out + live preview) with no external picker dep, a 44 dp
/// `CruxColorSwatch`, the `TokenEditor` + `TokenCategorySection`
/// per-token-override surface, the `PresetPicker` +
/// `PresetCard` + `PresetPreview` curated-preset surface, the
/// `ThemePackBrowser` install / export / activate / uninstall flow
/// with caller-supplied file pickers, and the
/// `ThemeAppearanceSection` drop-in composer that stitches the three
/// surfaces together for adopters who don't want a custom layout.
///
/// **Crux Desktop:** `cruxDesktopTheme` returns the one desktop
/// `ThemeData` every product builds on (every component theme set to the
/// desktop tokens, system UI font, no ink), and `cruxThemeForDevice` is the
/// one place the desktop layer is chosen over a product's phone and tablet
/// theme, by host platform. Both install `CruxDesktopTokens`, which the
/// dialog, toast and overflow-menu helpers in `crux_ide_layout` read.
///
/// `CruxChromeColors` and `CruxDesktopTokens` are declared in
/// `crux_ide_layout` (whose chrome reads them) and re-exported here, so
/// importing either package names the same types.
///
/// See the package README for the canonical adoption pattern.
library;

export 'package:crux_ide_layout/crux_ide_layout.dart'
    show CruxChromeColors, CruxDesktopTokens;

export 'src/chrome_theme_data.dart';
export 'src/crux_color_theme.dart';
export 'src/crux_desktop_theme.dart'
    hide cruxDesktopTheme, cruxUsesDesktopLayer;
export 'src/crux_theme_extension.dart';
export 'src/directory_theme_pack_store.dart';
export 'src/preset_token_overlay.dart';
export 'src/presets/builtin_presets.dart'
    hide legacyPresetIdAliases, migratePresetId;
export 'src/providers.dart';
export 'src/theme_pack.dart';
export 'src/theme_pack_codec.dart';
export 'src/theme_pack_service.dart';
export 'src/theme_pack_store.dart';
export 'src/theme_registry.dart';
export 'src/theme_token_category.dart';
// `ColorPickerDialog` (the widget), `colorFromHex` and `hexFromColor`
// are internal: no consumer across the eight product repos references
// them, `showColorPickerDialog` is the documented entry point, and the
// hex helpers duplicate `ThemePackCodec.tryParseColor` /
// `encodeColor`, which are the public spelling. Keeping them out of the
// barrel keeps the Apache-2.0 compatibility surface honest.
export 'src/widgets/color_picker_dialog.dart'
    hide ColorPickerDialog, colorFromHex, hexFromColor;
export 'src/widgets/color_swatch.dart' hide CruxColorSwatch;
export 'src/widgets/preset_card.dart';
export 'src/widgets/preset_picker.dart';
export 'src/widgets/preset_preview.dart' hide PresetPreview;
export 'src/widgets/theme_appearance_section.dart';
export 'src/widgets/theme_appearance_strings.dart';
export 'src/widgets/theme_pack_browser.dart';
export 'src/widgets/token_category_section.dart';
export 'src/widgets/token_editor.dart' hide TokenEditor;
