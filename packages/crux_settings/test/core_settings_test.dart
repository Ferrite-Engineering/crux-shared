// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoreSettings.defaults', () {
    test('returns the documented suite-wide default values', () {
      const settings = CoreSettings.defaults();
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.autoReloadMode, AutoReloadMode.prompt);
      expect(settings.autoSaveIntervalSeconds, 60);
      expect(settings.locale, 'en');
      expect(settings.diagnosticsEnabled, isFalse);
      expect(settings.orientationLockMode, OrientationLockMode.auto);
      expect(settings.autoHideChromeSeconds, 3);
      expect(settings.userPluginDirectories, isEmpty);
      expect(settings.pluginSafetyAcknowledged, isFalse);
      expect(settings.pluginLoadingDisabled, isFalse);
      expect(settings.perPluginDisabled, isEmpty);
      // The shared default is product-neutral. Beta users still
      // have the retired 'wavecrux-dark' persisted; crux_theme's
      // `migratePresetId` handles them on the read path (see
      // crux_theme/test/preset_id_migration_test.dart).
      expect(settings.activeThemeName, 'crux-dark');
      expect(settings.themeOverrides, isEmpty);
      expect(settings.restoreTabsOnLaunch, isTrue);
    });
  });

  group('CoreSettings.copyWith', () {
    const original = CoreSettings.defaults();

    test('returns identical settings when no overrides are provided', () {
      expect(original.copyWith(), equals(original));
    });

    test('overrides only the specified fields', () {
      final updated = original.copyWith(
        themeMode: AppThemeMode.light,
        locale: 'ja',
        autoSaveIntervalSeconds: 120,
      );
      expect(updated.themeMode, AppThemeMode.light);
      expect(updated.locale, 'ja');
      expect(updated.autoSaveIntervalSeconds, 120);
      // Untouched fields stay at defaults.
      expect(updated.autoReloadMode, original.autoReloadMode);
      expect(updated.diagnosticsEnabled, original.diagnosticsEnabled);
      expect(updated.restoreTabsOnLaunch, original.restoreTabsOnLaunch);
    });

    test('copyWith handles every field independently', () {
      final updated = original.copyWith(
        themeMode: AppThemeMode.system,
        autoReloadMode: AutoReloadMode.auto,
        autoSaveIntervalSeconds: 30,
        locale: 'zh_CN',
        diagnosticsEnabled: true,
        orientationLockMode: OrientationLockMode.landscapeLock,
        autoHideChromeSeconds: 7,
        userPluginDirectories: const ['/tmp/plugins'],
        pluginSafetyAcknowledged: true,
        pluginLoadingDisabled: true,
        perPluginDisabled: const {'foo': true},
        activeThemeName: 'solarized-dark',
        themeOverrides: const {'canvas.background': '#001122'},
        restoreTabsOnLaunch: false,
      );
      expect(updated.themeMode, AppThemeMode.system);
      expect(updated.autoReloadMode, AutoReloadMode.auto);
      expect(updated.autoSaveIntervalSeconds, 30);
      expect(updated.locale, 'zh_CN');
      expect(updated.diagnosticsEnabled, isTrue);
      expect(updated.orientationLockMode, OrientationLockMode.landscapeLock);
      expect(updated.autoHideChromeSeconds, 7);
      expect(updated.userPluginDirectories, ['/tmp/plugins']);
      expect(updated.pluginSafetyAcknowledged, isTrue);
      expect(updated.pluginLoadingDisabled, isTrue);
      expect(updated.perPluginDisabled, {'foo': true});
      expect(updated.activeThemeName, 'solarized-dark');
      expect(updated.themeOverrides, {'canvas.background': '#001122'});
      expect(updated.restoreTabsOnLaunch, isFalse);
    });
  });

  group('CoreSettings equality', () {
    test('two default instances are equal', () {
      const a = CoreSettings.defaults();
      const b = CoreSettings.defaults();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing scalar fields make settings unequal', () {
      const a = CoreSettings.defaults();
      final b = a.copyWith(locale: 'ja');
      expect(a, isNot(equals(b)));
    });

    test('equality compares list contents, not identity', () {
      final a = const CoreSettings.defaults().copyWith(
        userPluginDirectories: const ['/a', '/b'],
      );
      final b = const CoreSettings.defaults().copyWith(
        userPluginDirectories: const ['/a', '/b'],
      );
      expect(a, equals(b));
    });

    test('list-order differences are detected', () {
      final a = const CoreSettings.defaults().copyWith(
        userPluginDirectories: const ['/a', '/b'],
      );
      final b = const CoreSettings.defaults().copyWith(
        userPluginDirectories: const ['/b', '/a'],
      );
      expect(a, isNot(equals(b)));
    });

    test('map content differences are detected', () {
      final a = const CoreSettings.defaults().copyWith(
        themeOverrides: const {'a': '1'},
      );
      final b = const CoreSettings.defaults().copyWith(
        themeOverrides: const {'a': '2'},
      );
      expect(a, isNot(equals(b)));
    });

    test('map value differences change the hash', () {
      // The hash previously folded in map keys only, so two settings
      // differing only in a toggle's value (or an override's color) were
      // unequal under == yet always collided.
      final a = const CoreSettings.defaults().copyWith(
        themeOverrides: const {'a': '1'},
        perPluginDisabled: const {'p': true},
      );
      final b = const CoreSettings.defaults().copyWith(
        themeOverrides: const {'a': '2'},
        perPluginDisabled: const {'p': true},
      );
      final c = const CoreSettings.defaults().copyWith(
        themeOverrides: const {'a': '1'},
        perPluginDisabled: const {'p': false},
      );
      expect(a.hashCode, isNot(equals(b.hashCode)));
      expect(a.hashCode, isNot(equals(c.hashCode)));
    });
  });
}
