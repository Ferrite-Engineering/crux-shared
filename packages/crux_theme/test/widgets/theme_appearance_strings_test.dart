// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeAppearanceStringsEn', () {
    const strings = ThemeAppearanceStringsEn();

    test('exposes a non-empty section title and subtitle', () {
      expect(strings.sectionTitle, isNotEmpty);
      expect(strings.sectionSubtitle, isNotEmpty);
    });

    test('exposes non-empty section headings', () {
      expect(strings.presetSectionHeading, isNotEmpty);
      expect(strings.tokenOverridesSectionHeading, isNotEmpty);
      expect(strings.themePackBrowserSectionHeading, isNotEmpty);
    });

    test('exposes non-empty preset picker strings', () {
      expect(strings.activePresetIndicatorLabel, isNotEmpty);
      expect(strings.activatePresetTooltip, isNotEmpty);
      expect(strings.noPresetsAvailableMessage, isNotEmpty);
    });

    test('brightnessLabel varies with the isDark argument', () {
      final dark = strings.brightnessLabel(isDark: true);
      final light = strings.brightnessLabel(isDark: false);
      expect(dark, isNotEmpty);
      expect(light, isNotEmpty);
      expect(dark, isNot(equals(light)));
    });

    test('exposes non-empty token editor strings', () {
      expect(strings.editTokenColorTooltip, isNotEmpty);
      expect(strings.resetTokenToDefaultTooltip, isNotEmpty);
      expect(strings.emptyTokenCategoryMessage, isNotEmpty);
    });

    test('category collapse / expand labels echo the category name', () {
      final collapse = strings.collapseCategoryLabel('Canvas');
      final expand = strings.expandCategoryLabel('Canvas');
      expect(collapse, contains('Canvas'));
      expect(expand, contains('Canvas'));
      expect(collapse, isNot(equals(expand)));
    });

    test('exposes non-empty color picker strings', () {
      expect(strings.colorPickerDialogTitle, isNotEmpty);
      expect(strings.colorPickerHexLabel, isNotEmpty);
      expect(strings.colorPickerRgbLabel, isNotEmpty);
      expect(strings.colorPickerHsvLabel, isNotEmpty);
      expect(strings.colorPickerHueLabel, isNotEmpty);
      expect(strings.colorPickerSaturationLabel, isNotEmpty);
      expect(strings.colorPickerValueLabel, isNotEmpty);
      expect(strings.colorPickerPreviewLabel, isNotEmpty);
      expect(strings.colorPickerOkLabel, isNotEmpty);
      expect(strings.colorPickerCancelLabel, isNotEmpty);
    });

    test('invalidHexMessage echoes the offending input', () {
      final message = strings.invalidHexMessage('#NOTAHEX');
      expect(message, contains('#NOTAHEX'));
    });

    test('exposes non-empty theme pack browser strings', () {
      expect(strings.importThemePackButtonLabel, isNotEmpty);
      expect(strings.exportCurrentThemeButtonLabel, isNotEmpty);
      expect(strings.installedPacksHeading, isNotEmpty);
      expect(strings.noInstalledPacksMessage, isNotEmpty);
      expect(strings.activatePackButtonLabel, isNotEmpty);
      expect(strings.uninstallPackButtonLabel, isNotEmpty);
    });

    test('confirmation dialog body and messages echo their arguments', () {
      expect(
        strings.confirmUninstallDialogBody('my-pack'),
        contains('my-pack'),
      );
      expect(strings.importFailedMessage('disk full'), contains('disk full'));
      expect(strings.importSucceededMessage('new-pack'), contains('new-pack'));
      expect(
        strings.exportSucceededMessage('/tmp/my.crux-theme.json'),
        contains('/tmp/my.crux-theme.json'),
      );
      expect(
        strings.exportFailedMessage('permission denied'),
        contains('permission denied'),
      );
    });

    test('confirmation dialog cancel / confirm labels are non-empty', () {
      expect(strings.confirmUninstallDialogTitle, isNotEmpty);
      expect(strings.confirmUninstallCancelLabel, isNotEmpty);
      expect(strings.confirmUninstallConfirmLabel, isNotEmpty);
    });
  });

  group('ThemeAppearanceStrings subclass contract', () {
    test('a custom subclass can swap every getter', () {
      const strings = _TestStrings();
      expect(strings.sectionTitle, 'custom-section');
      expect(strings.brightnessLabel(isDark: true), 'dark!');
      expect(strings.brightnessLabel(isDark: false), 'light!');
      expect(strings.invalidHexMessage('zz'), 'bad: zz');
      expect(
        strings.confirmUninstallDialogBody('demo'),
        'confirm? demo',
      );
    });
  });
}

class _TestStrings extends ThemeAppearanceStrings {
  const _TestStrings();

  @override
  String get sectionTitle => 'custom-section';

  @override
  String get sectionSubtitle => 'custom-subtitle';

  @override
  String get presetSectionHeading => 'custom-presets';

  @override
  String get tokenOverridesSectionHeading => 'custom-tokens';

  @override
  String get themePackBrowserSectionHeading => 'custom-packs';

  @override
  String get activePresetIndicatorLabel => 'custom-active';

  @override
  String get activatePresetTooltip => 'custom-activate';

  @override
  String get noPresetsAvailableMessage => 'custom-no-presets';

  @override
  String brightnessLabel({required bool isDark}) => isDark ? 'dark!' : 'light!';

  @override
  String get editTokenColorTooltip => 'custom-edit';

  @override
  String get resetTokenToDefaultTooltip => 'custom-reset';

  @override
  String get emptyTokenCategoryMessage => 'custom-empty';

  @override
  String collapseCategoryLabel(String categoryDisplayName) =>
      'collapse $categoryDisplayName';

  @override
  String expandCategoryLabel(String categoryDisplayName) =>
      'expand $categoryDisplayName';

  @override
  String get colorPickerDialogTitle => 'custom-title';

  @override
  String get colorPickerHexLabel => 'custom-hex';

  @override
  String get colorPickerRgbLabel => 'custom-rgb';

  @override
  String get colorPickerHsvLabel => 'custom-hsv';

  @override
  String get colorPickerHueLabel => 'custom-hue';

  @override
  String get colorPickerSaturationLabel => 'custom-sat';

  @override
  String get colorPickerValueLabel => 'custom-val';

  @override
  String get colorPickerPreviewLabel => 'custom-preview';

  @override
  String get colorPickerOkLabel => 'custom-ok';

  @override
  String get colorPickerCancelLabel => 'custom-cancel';

  @override
  String invalidHexMessage(String input) => 'bad: $input';

  @override
  String get importThemePackButtonLabel => 'custom-import';

  @override
  String get exportCurrentThemeButtonLabel => 'custom-export';

  @override
  String get installedPacksHeading => 'custom-installed';

  @override
  String get noInstalledPacksMessage => 'custom-none';

  @override
  String get activatePackButtonLabel => 'custom-activate-pack';

  @override
  String get uninstallPackButtonLabel => 'custom-uninstall';

  @override
  String get confirmUninstallDialogTitle => 'custom-confirm-title';

  @override
  String confirmUninstallDialogBody(String packId) => 'confirm? $packId';

  @override
  String get confirmUninstallCancelLabel => 'custom-confirm-cancel';

  @override
  String get confirmUninstallConfirmLabel => 'custom-confirm-confirm';

  @override
  String importFailedMessage(String reason) => 'import failed: $reason';

  @override
  String importSucceededMessage(String packId) => 'import ok: $packId';

  @override
  String exportSucceededMessage(String destinationPath) =>
      'export ok: $destinationPath';

  @override
  String exportFailedMessage(String reason) => 'export failed: $reason';
}
