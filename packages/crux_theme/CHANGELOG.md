## Unreleased

- **Export namespace narrowed by 7 symbols.** `CruxColorSwatch`, `PresetPreview`, `TokenEditor`, `cruxDesktopTheme`, `cruxUsesDesktopLayer`, `legacyPresetIdAliases`, `migratePresetId` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

- **`PresetPreview`: the built-in Crux Dark and Crux Light presets show
  filled swatches.** They state no tokens, so each swatch resolved to the
  registry's transparent "use the product's value" sentinel and painted
  nothing. A transparent swatch now shows the colour the preset renders as in
  the product's theme for the preset's brightness and the platform contrast.
  Presets that state their tokens are unchanged.

- **`cruxDesktopTheme`: the focus ring, neutral secondary buttons, card
  radius and regular-weight menus.** Keyboard focus on a button or a text
  field now draws the ring the owned controls draw (a primary stroke 2 px
  outside, 1.5 px or 2.5 px in high contrast) through the button's focused
  shape (`CruxFocusRingShape`) and the field's focused border
  (`CruxFocusRingInputBorder`), instead of recolouring the control's own
  border. The outlined button (Browse…) is neutral: `onSurface` text on a
  flat face with a 1 px `outlineVariant` border that lifts to `outline` on
  hover. A filled button darkens on hover and press in light as in dark.
  Cards take the 6 px group radius (`CruxDesktopTokens.groupRadius`). Menu,
  pop-up menu and `DropdownMenu` text is pinned to regular weight.

- **`cruxDesktopTheme`, `cruxThemeForDevice`, `cruxUsesDesktopLayer`.** The
  Crux Desktop `ThemeData` over a product's `ColorScheme`: every component
  theme at the desktop tokens (28 px controls, 4 / 6 / 8 px radii, 13 / 12 /
  14 px type in the platform UI font, overlays without ink, a 1.5 px focus
  ring or 2.5 px in high contrast, an 18 % dialog scrim), WaveCrux's tuned
  card, list, input, tooltip, menu, menu bar, switch and scrollbar themes
  lifted in, and `CruxDesktopTokens` installed. `cruxThemeForDevice` picks it
  for macOS, Windows, Linux and the web and the product's own theme for iOS
  and Android, by platform and never by window size. `applyChromeTokens`
  layers over it unchanged.
- **The theme widgets use the Crux Desktop components.** The colour picker
  opens through `showCruxDialog` in a `CruxDialog` (non-dismissible: it holds
  a typed hex value; Enter applies), the theme-pack browser's uninstall is
  `confirmCruxDestructiveAction`, and its messages are the suite toasts, with
  failures through `showCruxErrorSnack`.
- **New dependency on `crux_ide_layout`**, which now declares
  `CruxChromeColors` and `CruxDesktopTokens`; both are re-exported here, so
  existing imports are unchanged.

- The branded presets complete their chrome from their own palettes. In
  Solarized Dark, Oscilloscope and OLED XR, `toolbar.iconActive` and
  `splitter.hover` take the palette's primary (#B58900, #00FF41, #FFD400), and
  `splitter` takes its minor-tick colour, raised to 3:1 against the panel and
  scaffold surfaces (#657F87, #256A25, #5C5C5C). A toggled toolbar glyph and
  the pane resizers therefore stop following the host product's `primary` and
  `outlineVariant` under these presets. High Contrast Dark, which declared no
  chrome, now declares all fourteen tokens: black surfaces, white text and
  icons, yellow (#FFFF00) for the active glyph and the hovered resizer, and a
  #666666 resizer at rest. Its chrome changes visibly in every product. The
  declared toolbar and status bar values are unchanged. Every value and its
  contrast is pinned in `builtin_presets_test.dart`.

- `CruxChromeColors` gains `toolbarBackground` and `toolbarIcon`, which
  `applyChromeTokens` fills from `toolbar.background` and `toolbar.icon`, so
  the two tokens reach the application toolbar as well as the `AppBar`s they
  already coloured. Unset, the toolbar keeps its Material colours. The three
  branded presets that declare these tokens (Solarized Dark, Oscilloscope,
  OLED XR) now paint their main toolbar with the values their app bars
  already showed; whether those values are the right ones is a separate
  design decision.

- Fix: eight shared chrome tokens — `toolbar.iconActive`,
  `statusBar.background`, `statusBar.foreground`, `splitter`, `splitter.hover`,
  `tabBar.background`, `tabBar.selected`, `tabBar.label` — were registered,
  preset, editable in Settings → Appearance and settable by theme packs, yet
  no widget painted with them, so an edit silently did nothing.
  `applyChromeTokens` now resolves them into a new `CruxChromeColors`
  `ThemeExtension` on the `ThemeData` it returns, and the shared status bar,
  pane resizers, document tab bar and toolbar read it. `ChromeTokens` gains a
  constant for each.
- The three presets that declared those tokens (`solarized-dark`,
  `oscilloscope`, `oled-xr`) now declare only the colour each surface already
  showed, so no preset changed appearance except the one below:
  `statusBar.background` and `tabBar.selected` equal
  `panel.header.background`, and `statusBar.foreground` is
  `panel.header.foreground` at alpha `0xBF`. The other five tokens are dropped
  from them because those surfaces showed the host product's own Material
  colours; they inherit. Packs that set any of these tokens still import, and
  now take effect. The values the presets declared before are recorded in
  `builtin_presets_test.dart`. Preset cards whose preview samples these tokens
  show the new values.
- Accessibility: **Solarized Dark's status bar text is brighter.** It has
  always painted `#93A1A1` at 75 % opacity over `#002B36`, which is 3.76:1,
  below the WCAG 2.1 AA minimum of 4.5:1 for text. Its `statusBar.foreground`
  is now the opaque `#93A1A1` the preset originally declared, 5.61:1. This is
  a visible change for anyone using Solarized Dark; no other preset changes.
- `preset_contrast_test.dart` measures a translucent foreground blended over
  its background. Every preset's status bar, panel header and toolbar pair now
  meets AA, so it records no shortfalls.
- Docs: the README's worked example looked up the retired `wavecrux-dark` id,
  and it and the `PresetPicker` / `PresetPreview` docs named a canvas token
  that no longer exists. A "Chrome tokens" section lists what each token
  paints.

## 0.3.0

- Shared chrome-token catalog: `registerCruxThemeChromeTokens` /
  `chromeTokens`, plus the `applyChromeTokens` and `themeModeFromBrightness`
  helpers, so products recolor the scaffold / app bar / card / panel surfaces
  from the active preset instead of each maintaining its own chrome mapping.
- Sixth built-in preset, `oled-xr` (true-black OLED). The pack now ships six
  brand-neutral presets.
- Preset ids are brand-neutral: `wavecrux-dark` / `wavecrux-light` were renamed
  to `crux-dark` / `crux-light`. The old ids remain permanently accepted on the
  read path via `migratePresetId` / `legacyPresetIdAliases`, so persisted
  settings and shared packs keep resolving.
- Fix: 8-digit hex is now parsed and formatted as `RRGGBBAA` in both the color
  picker (`colorFromHex` / `hexFromColor`) and `ThemePackCodec`. The picker
  previously read 8-digit hex as `AARRGGBB`, silently swapping alpha and red on
  any hex copied out of a theme-pack document.
- Fix: preset cards size to their content instead of a fixed aspect ratio, and
  theme-pack action buttons wrap rather than overflow narrow columns.

## 0.2.0

- `ThemeAppearanceStrings` — abstract interface for caller-supplied
  L10N covering every string the new widgets render (section title /
  subtitle, sub-section headings, preset picker labels, token editor
  labels, color picker labels, theme pack browser labels, snackbar
  messages). `ThemeAppearanceStringsEn` ships as the English default
  so adopters can drop the widgets in without wiring localization
  first.
- `ColorPickerDialog` — modal color picker built from Material 3
  primitives: HSV sliders (hue / saturation / value), a permissive
  hex text field (`RRGGBB` or `AARRGGBB`, with or without a leading
  `#`), a read-only RGB read-out row, and a live before / after
  preview swatch. `showColorPickerDialog` is the convenience
  launcher. No external picker dependency — products that want
  richer pickers (eyedropper, palette history) plug their own picker
  in via `TokenEditor` callbacks.
- `colorFromHex` / `hexFromColor` — public hex parser and formatter
  used internally by the dialog and exposed for adopter token-editor
  consumers and tests.
- `CruxColorSwatch` — small clickable color swatch (24 dp visual,
  44 dp hit area on touch). Tapping opens the picker and reports
  back through `onColorPicked`. Passing `onColorPicked: null` makes
  it read-only.
- `TokenEditor` — per-token row consuming `cruxColorThemeProvider`.
  Renders the descriptor's display name + optional description, an
  interactive `CruxColorSwatch` showing the current value (resolved
  via `ThemeRegistry`'s descriptor-default fallback), and a reset-to-
  default button that activates only when the active theme has an
  explicit override. Edits flow through `notifier.applyOverrides`
  and the reset rebuilds the token table via `notifier.activate`.
- `TokenCategorySection` — expandable Material 3 card grouping one
  `TokenEditor` per descriptor inside a `ThemeTokenCategory`.
  Header is tappable with chevron, starts collapsed by default,
  optional `initiallyExpanded` + `onExpansionChanged` callbacks let
  host products restore and persist per-category expansion state.
- `PresetPreview` — small fixed-grid color preview sampled from a
  theme; defaults to the first 8 tokens in `ThemeRegistry`
  registration order, accepts an explicit list of `(categoryId,
  tokenId)` pairs to highlight the host product's most-distinguishing
  tokens.
- `PresetCard` — tappable card with brightness icon, display name,
  embedded `PresetPreview`, and an outline + `Semantics(selected: true)`
  marker when `isActive` is `true`.
- `PresetPicker` — responsive grid (3 cols ≥900 dp, 2 cols ≥600 dp,
  1 col below) of `PresetCard`s. Tapping activates the preset via
  `cruxColorThemeProvider.notifier.activate`. Empty-state message
  rendered when the presets list is empty.
- `ThemePackBrowser` — installed-packs list with import / export /
  activate / uninstall actions. File picking is caller-supplied via
  required `pickPackFile` and `pickExportLocation` callbacks
  (`PickPackFile` / `PickExportLocation` typedefs) so `crux_theme`
  stays `flutter_riverpod`-only. Activate flows through
  `cruxColorThemeProvider`. Uninstall presents a confirmation dialog.
- `ThemeAppearanceSection` — default top-level composer stitching
  `PresetPicker`, one `TokenCategorySection` per registered
  category, and `ThemePackBrowser` into a single drop-in widget.
  `showAdvancedOverrides: false` collapses the token-override block
  for compact mobile layouts; `trailingActions` lets adopters append
  product-specific widgets without subclassing; `previewTokens`
  forwards to the embedded `PresetPicker`.
- 35 widget + unit tests cover the strings interface (full surface +
  custom subclass), the dialog and swatch (render + return values +
  hex round-trip + hit-area floor + read-only path), token editor
  (display + enabled/disabled reset + notifier-driven override
  clear), category section (collapsed-by-default + toggle +
  callback), preset trio (count + brightness icon + active marker +
  notifier activation + empty state), and the section composer
  (heading render + composed surface order + advanced-overrides
  toggle + trailingActions).
- Full install-and-list / uninstall-and-refresh integration tests for
  `ThemePackBrowser` are deferred — `flutter_test`'s
  `pumpAndSettle` hangs on the FutureBuilder's real-IO future.
  Coverage of the underlying install / list / uninstall operations
  lives in `theme_pack_service_test.dart` and is exercised
  indirectly when host products integration-test their own Settings
  surfaces.

## 0.1.0

- Initial release. Foundation extraction lifted from WaveCrux.
- `CruxColorTheme` — immutable theme with category-keyed
  `Map<String, Map<String, Color>>` token storage.
- `ThemeTokenCategory` / `ThemeTokenDescriptor` — registration schema each
  product fills with its product-specific token categories.
- `ThemePack` / `ThemePackCodec` — JSON pack representation and the strict
  encode/decode pipeline (`schemaVersion: 1`).
- `ThemePackService` — install / list / uninstall / validate file-system
  operations against a user theme directory.
- `builtinPresets()` — five built-in `CruxColorTheme` presets
  (`wavecrux-dark`, `wavecrux-light`, `solarized-dark`,
  `high-contrast-dark`, `oscilloscope`) with the canvas + chrome token
  set WaveCrux currently uses.
- `ThemeRegistry` — runtime registration surface for token categories,
  plus the `merge` operation that layers a quick-override map on top of a
  base preset.
- `cruxColorThemeProvider` — Riverpod `NotifierProvider` holding the
  active theme; consumers replace it via `overrideWith` to drive the app.
- `CruxThemeExtension` — `ThemeExtension<CruxThemeExtension>` so Flutter
  widgets read tokens through `Theme.of(context)`.
