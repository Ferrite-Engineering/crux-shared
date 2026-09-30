# crux_theme

Cross-suite named-token color theming infrastructure for the EDACrux
suite.

This package supplies the named-token color theme engine, the
`.crux-theme.json` pack format, the six built-in brand-neutral presets, the
Riverpod-backed `cruxColorThemeProvider`, and the
`ThemeExtension<CruxThemeExtension>` that Flutter widgets read through
`Theme.of(context)`. Every Crux product consumes the same engine and
registers its own
`ThemeTokenCategory` set on top.

## Status

**Foundation + Settings → Appearance UI (`0.2.0`).**

| Layer | Surfaces |
|---|---|
| Domain | `CruxColorTheme`, `ThemeTokenCategory`, `ThemeTokenDescriptor`, `ThemePack`, `ThemePackHeader` |
| Persistence | `ThemePackCodec`, `ThemePackService`, `ThemePackValidation` |
| Presets | `builtinPresets()` — five WaveCrux-canonical presets |
| Registry | `ThemeRegistry` (token-category registration + merge) |
| Riverpod | `cruxColorThemeProvider` (`NotifierProvider<CruxColorThemeNotifier, CruxColorTheme>`) |
| Flutter | `CruxThemeExtension` for `ThemeData.extensions` |
| Settings strings | `ThemeAppearanceStrings` (abstract) + `ThemeAppearanceStringsEn` (default) |
| Color picker | `ColorPickerDialog`, `showColorPickerDialog`, `CruxColorSwatch`, `colorFromHex` / `hexFromColor` |
| Token editor | `TokenEditor`, `TokenCategorySection` |
| Preset picker | `PresetPicker`, `PresetCard`, `PresetPreview` |
| Theme pack browser | `ThemePackBrowser` + `PickPackFile` / `PickExportLocation` callback typedefs |
| Section composer | `ThemeAppearanceSection` |

**Deferred to follow-on releases:**

- Product migrations: WaveCrux off `WavecruxColorTheme`; future Crux
  products from their per-product theme types.
- Palette-shaped tokens (`Map<String, List<Color>>` alongside the
  scalar token table). The model stores one `Color` per token id;
  consumers that need an N-way rotating signal palette (WaveCrux's
  `canvas.signal.palette` is the canonical example) keep that state
  product-local for now.
- In-package ARB-generated localizations. Today the caller supplies
  strings via a `ThemeAppearanceStrings` subclass that wraps their
  product's `AppLocalizations`.

## Mental model

A `CruxColorTheme` is a flat `Map<String, Map<String, Color>>` of
**category → token → color** entries plus an `id`, a `displayName`, and
a `Brightness`. Every product names its own token categories
(`canvas`, `chrome`, `severity`, `status`, …). The package never
hard-codes a token id; the engine, the JSON pack format, and the
Settings UI are entirely schema-driven.

Each product describes its tokens at startup by registering one or more
`ThemeTokenCategory` instances on the shared `ThemeRegistry`. A
`ThemeTokenCategory` carries a list of `ThemeTokenDescriptor`s
(`(id, displayName, lightDefault, darkDefault, description?)`) that
drive the Settings → Appearance grid and supply the fallback colors a
theme pack can omit.

The active `CruxColorTheme` lives behind `cruxColorThemeProvider`.
Consumers `overrideWith` the provider's notifier to wire their own
boot logic (initial preset selection, persistence). The provider
exposes mutators `activate(theme)`, `applyOverrides(map)`, and
`reset()`; the `merge` operation is also available statically on
`ThemeRegistry`.

The Flutter integration is `CruxThemeExtension` — a
`ThemeExtension<CruxThemeExtension>` that wraps the active theme and
exposes `color(category, token)` / `colorOr(category, token, fallback)`
for widget code. Wire it into `ThemeData.extensions` and read it via
`Theme.of(context).extension<CruxThemeExtension>()!`.

## Worked example

```dart
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const wavecruxCanvas = ThemeTokenCategory(
  id: 'canvas',
  displayName: 'Canvas',
  tokens: [
    ThemeTokenDescriptor(
      id: 'background',
      displayName: 'Background',
      lightDefault: Color(0xFFF5F5F5),
      darkDefault: Color(0xFF1A1A1A),
    ),
    ThemeTokenDescriptor(
      id: 'cursor.primary',
      displayName: 'Primary cursor',
      lightDefault: Color(0xFFE65100),
      darkDefault: Color(0xFFFFEE58),
    ),
  ],
);

void main() {
  // 1. Register product token categories at startup.
  ThemeRegistry.instance.registerCategory(wavecruxCanvas);

  // 2. Pick an initial theme (here Crux Dark, the suite default).
  final initial = builtinPresetById(cruxDarkPresetId)!;

  runApp(
    ProviderScope(
      overrides: [
        cruxColorThemeProvider.overrideWith(
          () => CruxColorThemeNotifier(initial: initial),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(cruxColorThemeProvider);
    return MaterialApp(
      theme: ThemeData(
        brightness: theme.brightness,
        extensions: [CruxThemeExtension(theme: theme)],
      ),
      home: Builder(
        builder: (ctx) {
          final cx = Theme.of(ctx).extension<CruxThemeExtension>()!;
          return Container(
            color: cx.color('canvas', 'background'),
          );
        },
      ),
    );
  }
}
```

## Chrome tokens

The shared `chrome` category (`chromeTokens`, registered with
`registerCruxThemeChromeTokens`) is the one token catalog every product
carries. A product folds the active theme into its `MaterialApp` with
`applyChromeTokens(base, CruxThemeExtension(theme: active))`, rebuilt from
`cruxColorThemeProvider`, and every token then reaches a painted surface, so
an edit in Settings → Appearance repaints at once:

| Token | Painted as | When the theme leaves it unset |
|---|---|---|
| `scaffold.background` | `ThemeData.scaffoldBackgroundColor` | the base theme's |
| `panel.background` | `ColorScheme.surface`, `CardTheme.color` | the base theme's |
| `panel.header.background` | `ColorScheme.surfaceContainerHighest` | `panel.background`, then the base theme's |
| `panel.header.foreground` | `ColorScheme.onSurface` | the base theme's |
| `toolbar.background` | `AppBarTheme.backgroundColor` | the base theme's |
| `toolbar.icon` | `AppBarTheme.foregroundColor` | the base theme's |
| `toolbar.iconActive` | a toggled-on `CruxToolbarButton` glyph | `primary` |
| `statusBar.background` | the `CruxStatusBar` surface | `surfaceContainerHighest` |
| `statusBar.foreground` | `CruxStatusBar` text, via `resolveTextStyle` | `onSurface` at 75 % |
| `splitter` | a `CruxIdeLayout` resizer at rest | `outlineVariant` |
| `splitter.hover` | the resizer hovered, dragged or focused | `primary` |
| `tabBar.background` | the `ViewerTabBar` strip | no fill |
| `tabBar.selected` | the active `ViewerTabBar` tab | `surfaceContainerHighest` |
| `tabBar.label` | every `ViewerTabBar` tab title | `bodyMedium`'s colour |

Material has no slot for the last eight, so `applyChromeTokens` resolves them
into a `CruxChromeColors` extension on the `ThemeData` it returns, and the
shared widgets read it with `CruxChromeColors.of(context)`. A widget argument
that sets a colour explicitly (`CruxStatusBar.backgroundColor`, a
`CruxIdeLayoutTheme` resizer colour) outranks the theme. A fully transparent
token value means "unset".

The three presets that declare chrome tokens (`solarized-dark`,
`oscilloscope`, `oled-xr`) set the last eight only where the value is the
colour the surface already showed, so wiring them recolored no preset; the
rest inherit. `builtin_presets_test.dart` pins those values next to the ones
the presets declared before.

## Settings → Appearance UI

The `0.2.0` widget set lets a product drop a complete Appearance
panel into its Settings screen without writing any custom layout:

```dart
import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key, required this.packDirectory});

  final Directory packDirectory;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ThemeAppearanceSection(
        presets: builtinPresets().values.toList(),
        packDirectory: packDirectory,
        strings: _MyAppThemeStrings(AppLocalizations.of(context)!),
        pickPackFile: () async {
          final picked = await fp.FilePicker.platform.pickFiles(
            type: fp.FileType.custom,
            allowedExtensions: ['json'],
          );
          final path = picked?.files.single.path;
          return path == null ? null : File(path);
        },
        pickExportLocation: () async {
          final destination = await fp.FilePicker.platform.saveFile(
            fileName: 'my-theme.crux-theme.json',
          );
          return destination == null ? null : File(destination);
        },
        // Optional — highlight the tokens that most distinguish your
        // product's themes in the preset preview swatch row.
        previewTokens: const [
          ('canvas', 'background'),
          ('canvas', 'cursor.primary'),
          ('canvas', 'signal.x.fill'),
          ('canvas', 'signal.z.line'),
        ],
      ),
    );
  }
}

class _MyAppThemeStrings extends ThemeAppearanceStrings {
  const _MyAppThemeStrings(this._l10n);

  final AppLocalizations _l10n;

  @override
  String get sectionTitle => _l10n.settingsAppearanceTitle;

  // ... override every getter to point at your own l10n strings.
  // See ThemeAppearanceStringsEn in lib/src/widgets/ for the full
  // surface and the EN defaults to mirror when wiring your own.
}
```

For finer control, the individual widgets — `PresetPicker`,
`TokenCategorySection`, `ThemePackBrowser`, `CruxColorSwatch`,
`showColorPickerDialog` — are exported separately so a product that
wants to weave product-specific shortcuts ("Quick canvas overrides"
for the four most-tweaked tokens, a "Reset to factory defaults"
button, GTKWave migration controls, etc.) into the layout can
compose its own panel from the same parts.

`pickPackFile` and `pickExportLocation` are caller-supplied so this
package never adds a `file_picker` (or share-sheet) dependency.
Products choose their own picker and pass it in — desktop
`file_picker`, mobile share sheets, or an in-test stub returning a
predetermined `File`.

## Scope boundaries

**In `crux_theme`:** the token-storage model, the registry, the pack
format, the codec, the file-system service, the six built-in presets,
the Riverpod provider, the `ThemeExtension`, the shared `chrome` catalog
with `applyChromeTokens` and `CruxChromeColors`, **and the Settings →
Appearance widget set** (preset picker, token editor, color picker,
theme pack browser, drop-in section composer).

**Per-product (in each product's repo):**

- Token category definitions beyond `chrome` (`canvas` for WaveCrux,
  other products' own categories, etc.).
- Compatibility extension methods or wrappers exposing per-product
  legacy getters (e.g. `theme.canvasBackground` on WaveCrux is a
  shim over `theme.color('canvas', 'background')`).
- Migration of incoming session / project files that referenced the
  old per-product theme types.
- An `AppLocalizations`-backed `ThemeAppearanceStrings` subclass so
  the widget set picks up the host product's ARB-generated strings.
- The file-picker bridge passed into `pickPackFile` /
  `pickExportLocation`.
- Product-specific shortcuts (e.g. WaveCrux's "Quick canvas
  overrides" surfacing the four most-tweaked tokens at the top of
  the Appearance panel) — compose using the exported widgets.

## Crux-shared workspace

This package is part of the `crux-shared` Melos workspace. Add it as a
path dependency in a consumer's `pubspec.yaml`:

```yaml
dependencies:
  crux_theme:
    path: ../crux-shared/packages/crux_theme
```

Run `melos run analyze` and `melos run test` at the workspace root to
verify changes across the suite.
