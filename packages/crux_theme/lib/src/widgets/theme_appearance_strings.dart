// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Strings rendered by the Settings → Appearance widgets shipped in
/// `crux_theme`.
///
/// Products supply a subclass that pulls localized strings from their
/// `AppLocalizations` so the widgets never bake in English text. The
/// English-only [ThemeAppearanceStringsEn] default is provided so callers
/// can drop the widgets into a prototype without wiring localization
/// first. Every field is an abstract getter so a future ARB-generated
/// implementation can slot in without changing call sites.
///
/// Strings are grouped by widget so adopters can see at a glance which
/// strings power which surface:
///
/// * **Section**: top-level `ThemeAppearanceSection` composer.
/// * **Preset picker**: `PresetPicker`, `PresetCard`, `PresetPreview`.
/// * **Token editor**: `TokenCategorySection`, `TokenEditor`, `ColorSwatch`.
/// * **Color picker**: `ColorPickerDialog`.
/// * **Theme pack browser**: `ThemePackBrowser`.
@immutable
abstract class ThemeAppearanceStrings {
  /// Const constructor for subclasses.
  const ThemeAppearanceStrings();

  // --- Section composer -----------------------------------------------

  /// Title rendered above the composed `ThemeAppearanceSection`.
  String get sectionTitle;

  /// Optional one-line subtitle rendered below the title. Implementations
  /// may return an empty string to suppress the subtitle.
  String get sectionSubtitle;

  /// Heading rendered above the preset picker block.
  String get presetSectionHeading;

  /// Heading rendered above the per-category token override block.
  String get tokenOverridesSectionHeading;

  /// Heading rendered above the theme-pack browser block.
  String get themePackBrowserSectionHeading;

  // --- Preset picker --------------------------------------------------

  /// Accessibility label rendered on the active preset card.
  String get activePresetIndicatorLabel;

  /// Tooltip shown when hovering an inactive preset card.
  String get activatePresetTooltip;

  /// Empty-state message rendered when the preset list is empty.
  String get noPresetsAvailableMessage;

  /// Accessibility label for the brightness icon. Implementations should
  /// vary the returned string with the brightness; the default returns
  /// `'Light theme'` or `'Dark theme'`.
  String brightnessLabel({required bool isDark});

  // --- Token editor ---------------------------------------------------

  /// Tooltip rendered over the per-token color swatch (open the picker).
  String get editTokenColorTooltip;

  /// Tooltip on the "reset to default" button when an override is active.
  String get resetTokenToDefaultTooltip;

  /// Empty-state message rendered when a registered category contains no
  /// tokens. Defensive — the registration API requires at least one.
  String get emptyTokenCategoryMessage;

  /// Accessibility label for the expand / collapse chevron on a
  /// `TokenCategorySection`. The widget passes the resolved
  /// `ThemeTokenCategory.displayName` so the label can include it.
  String collapseCategoryLabel(String categoryDisplayName);

  /// Accessibility label for the expand chevron, paired with
  /// [collapseCategoryLabel].
  String expandCategoryLabel(String categoryDisplayName);

  // --- Color picker ---------------------------------------------------

  /// Title shown at the top of the modal color picker dialog.
  String get colorPickerDialogTitle;

  /// Label rendered next to the hex input field.
  String get colorPickerHexLabel;

  /// Label rendered above the RGB read-out row.
  String get colorPickerRgbLabel;

  /// Label rendered above the HSV slider group.
  String get colorPickerHsvLabel;

  /// Label rendered next to the hue slider.
  String get colorPickerHueLabel;

  /// Label rendered next to the saturation slider.
  String get colorPickerSaturationLabel;

  /// Label rendered next to the value (brightness) slider.
  String get colorPickerValueLabel;

  /// Accessibility label for the live preview swatch.
  String get colorPickerPreviewLabel;

  /// "OK" / accept action label.
  String get colorPickerOkLabel;

  /// "Cancel" / dismiss action label.
  String get colorPickerCancelLabel;

  /// Error message shown when the user types an invalid hex string. The
  /// widget passes the offending input so the message can echo it back.
  String invalidHexMessage(String input);

  // --- Theme pack browser ---------------------------------------------

  /// Label of the "Import…" button that opens a file picker.
  String get importThemePackButtonLabel;

  /// Label of the "Export current theme…" button.
  String get exportCurrentThemeButtonLabel;

  /// Heading rendered above the installed-packs list.
  String get installedPacksHeading;

  /// Empty-state message rendered when the user has no installed packs.
  String get noInstalledPacksMessage;

  /// "Activate" action shown next to each installed pack row.
  String get activatePackButtonLabel;

  /// "Uninstall" action shown next to each installed pack row.
  String get uninstallPackButtonLabel;

  /// Title of the uninstall confirmation dialog.
  String get confirmUninstallDialogTitle;

  /// Body of the uninstall confirmation dialog. The widget passes the
  /// pack id so the message can echo it.
  String confirmUninstallDialogBody(String packId);

  /// "Cancel" action on the uninstall confirmation dialog.
  String get confirmUninstallCancelLabel;

  /// Destructive action on the uninstall confirmation dialog.
  String get confirmUninstallConfirmLabel;

  /// Snackbar / inline error shown when import fails. The widget passes
  /// the underlying message so the user has something actionable.
  String importFailedMessage(String reason);

  /// Snackbar / inline confirmation shown after a successful import.
  /// The widget passes the freshly installed pack id.
  String importSucceededMessage(String packId);

  /// Snackbar / inline confirmation shown after a successful export.
  /// The widget passes the export destination path.
  String exportSucceededMessage(String destinationPath);

  /// Snackbar / inline error shown when export fails.
  String exportFailedMessage(String reason);
}

/// Default English [ThemeAppearanceStrings] used when callers do not
/// supply their own. Mirrors the strings products typically pull from
/// their ARB files.
class ThemeAppearanceStringsEn extends ThemeAppearanceStrings {
  /// Creates the default English string set.
  const ThemeAppearanceStringsEn();

  @override
  String get sectionTitle => 'Appearance';

  @override
  String get sectionSubtitle =>
      'Pick a preset, edit individual colors, or manage theme packs.';

  @override
  String get presetSectionHeading => 'Presets';

  @override
  String get tokenOverridesSectionHeading => 'Color overrides';

  @override
  String get themePackBrowserSectionHeading => 'Theme packs';

  @override
  String get activePresetIndicatorLabel => 'Active preset';

  @override
  String get activatePresetTooltip => 'Activate preset';

  @override
  String get noPresetsAvailableMessage => 'No presets available.';

  @override
  String brightnessLabel({required bool isDark}) =>
      isDark ? 'Dark theme' : 'Light theme';

  @override
  String get editTokenColorTooltip => 'Edit color';

  @override
  String get resetTokenToDefaultTooltip => 'Reset to default';

  @override
  String get emptyTokenCategoryMessage => 'No tokens in this category.';

  @override
  String collapseCategoryLabel(String categoryDisplayName) =>
      'Collapse $categoryDisplayName';

  @override
  String expandCategoryLabel(String categoryDisplayName) =>
      'Expand $categoryDisplayName';

  @override
  String get colorPickerDialogTitle => 'Choose color';

  @override
  String get colorPickerHexLabel => 'Hex';

  @override
  String get colorPickerRgbLabel => 'RGB';

  @override
  String get colorPickerHsvLabel => 'HSV';

  @override
  String get colorPickerHueLabel => 'Hue';

  @override
  String get colorPickerSaturationLabel => 'Saturation';

  @override
  String get colorPickerValueLabel => 'Value';

  @override
  String get colorPickerPreviewLabel => 'Selected color preview';

  @override
  String get colorPickerOkLabel => 'OK';

  @override
  String get colorPickerCancelLabel => 'Cancel';

  @override
  String invalidHexMessage(String input) => 'Invalid color: $input';

  @override
  String get importThemePackButtonLabel => 'Import theme pack…';

  @override
  String get exportCurrentThemeButtonLabel => 'Export current theme…';

  @override
  String get installedPacksHeading => 'Installed packs';

  @override
  String get noInstalledPacksMessage => 'No theme packs installed.';

  @override
  String get activatePackButtonLabel => 'Activate';

  @override
  String get uninstallPackButtonLabel => 'Uninstall';

  @override
  String get confirmUninstallDialogTitle => 'Uninstall theme pack?';

  @override
  String confirmUninstallDialogBody(String packId) =>
      'Remove the theme pack "$packId"? This cannot be undone.';

  @override
  String get confirmUninstallCancelLabel => 'Cancel';

  @override
  String get confirmUninstallConfirmLabel => 'Uninstall';

  @override
  String importFailedMessage(String reason) =>
      'Failed to import theme pack: $reason';

  @override
  String importSucceededMessage(String packId) =>
      'Installed theme pack "$packId".';

  @override
  String exportSucceededMessage(String destinationPath) =>
      'Exported theme to $destinationPath.';

  @override
  String exportFailedMessage(String reason) =>
      'Failed to export theme: $reason';
}
