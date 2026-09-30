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
/// Product migrations off per-product theme types (WaveCrux off
/// `WavecruxColorTheme`, future Crux products from their per-product
/// 1.x theme types) ship in follow-on releases.
///
/// See the package README for the canonical adoption pattern.
library;

export 'src/chrome_theme_data.dart';
export 'src/crux_chrome_colors.dart';
export 'src/crux_color_theme.dart';
export 'src/crux_theme_extension.dart';
export 'src/directory_theme_pack_store.dart';
export 'src/preset_token_overlay.dart';
export 'src/presets/builtin_presets.dart';
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
export 'src/widgets/color_swatch.dart';
export 'src/widgets/preset_card.dart';
export 'src/widgets/preset_picker.dart';
export 'src/widgets/preset_preview.dart';
export 'src/widgets/theme_appearance_section.dart';
export 'src/widgets/theme_appearance_strings.dart';
export 'src/widgets/theme_pack_browser.dart';
export 'src/widgets/token_category_section.dart';
export 'src/widgets/token_editor.dart';
