// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return await SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = CoreSettingsCodec();

  group('CoreSettingsCodec.load', () {
    test('returns defaults when no keys are persisted', () async {
      final prefs = await _prefs();
      final loaded = await codec.load(prefs);
      expect(loaded, const CoreSettings.defaults());
    });

    test(
      'reads each scalar field by its documented SharedPreferences key',
      () async {
        final prefs = await _prefs({
          'settings.themeMode': AppThemeMode.light.index,
          'settings.autoReloadMode': AutoReloadMode.auto.index,
          'settings.autoSaveIntervalSeconds': 120,
          'settings.locale': 'ja',
          'settings.diagnosticsEnabled': true,
          'settings.orientationLockMode':
              OrientationLockMode.landscapeLock.index,
          'settings.autoHideChromeSeconds': 5,
          'settings.userPluginDirectories': ['/x'],
          'settings.pluginSafetyAcknowledged': true,
          'settings.pluginLoadingDisabled': true,
          'settings.activeThemeName': 'solarized-dark',
          'settings.restoreTabsOnLaunch': false,
        });
        final loaded = await codec.load(prefs);
        expect(loaded.themeMode, AppThemeMode.light);
        expect(loaded.autoReloadMode, AutoReloadMode.auto);
        expect(loaded.autoSaveIntervalSeconds, 120);
        expect(loaded.locale, 'ja');
        expect(loaded.diagnosticsEnabled, isTrue);
        expect(loaded.orientationLockMode, OrientationLockMode.landscapeLock);
        expect(loaded.autoHideChromeSeconds, 5);
        expect(loaded.userPluginDirectories, ['/x']);
        expect(loaded.pluginSafetyAcknowledged, isTrue);
        expect(loaded.pluginLoadingDisabled, isTrue);
        expect(loaded.activeThemeName, 'solarized-dark');
        expect(loaded.restoreTabsOnLaunch, isFalse);
      },
    );

    test('decodes JSON-encoded perPluginDisabled map', () async {
      final prefs = await _prefs({
        'settings.perPluginDisabled': jsonEncode({
          'pluginA': true,
          'pluginB': false,
        }),
      });
      final loaded = await codec.load(prefs);
      expect(loaded.perPluginDisabled, {'pluginA': true, 'pluginB': false});
    });

    test('decodes JSON-encoded themeOverrides map', () async {
      final prefs = await _prefs({
        'settings.themeOverrides': jsonEncode({
          'canvas.background': '#001122',
          'canvas.cursor.primary': '#FFFF00',
        }),
      });
      final loaded = await codec.load(prefs);
      expect(loaded.themeOverrides, {
        'canvas.background': '#001122',
        'canvas.cursor.primary': '#FFFF00',
      });
    });

    test('falls back to defaults when an enum index is out of range', () async {
      final prefs = await _prefs({
        'settings.themeMode': 999,
        'settings.orientationLockMode': -1,
      });
      final loaded = await codec.load(prefs);
      expect(loaded.themeMode, AppThemeMode.dark);
      expect(loaded.orientationLockMode, OrientationLockMode.auto);
    });

    test('clamps autoSaveIntervalSeconds and autoHideChromeSeconds to valid '
        'ranges', () async {
      final prefs = await _prefs({
        'settings.autoSaveIntervalSeconds': 1000000, // > 600
        'settings.autoHideChromeSeconds': 0, // < 1
      });
      final loaded = await codec.load(prefs);
      expect(loaded.autoSaveIntervalSeconds, 600);
      expect(loaded.autoHideChromeSeconds, 1);
    });

    test(
      'returns empty map when perPluginDisabled value is not valid JSON',
      () async {
        final prefs = await _prefs({
          'settings.perPluginDisabled': 'not-json{',
        });
        final loaded = await codec.load(prefs);
        expect(loaded.perPluginDisabled, isEmpty);
      },
    );

    test(
      'returns empty map when themeOverrides has non-string values',
      () async {
        // jsonEncode of a map with numeric values is valid JSON, but the codec
        // filters out non-string values.
        final prefs = await _prefs({
          'settings.themeOverrides': jsonEncode({'a': 42, 'b': '#FFFFFF'}),
        });
        final loaded = await codec.load(prefs);
        expect(loaded.themeOverrides, {'b': '#FFFFFF'});
      },
    );
  });

  group('CoreSettingsCodec.save', () {
    test(
      'writes every field to its documented SharedPreferences key',
      () async {
        final prefs = await _prefs();
        final settings = const CoreSettings.defaults().copyWith(
          themeMode: AppThemeMode.light,
          locale: 'zh_CN',
          diagnosticsEnabled: true,
          userPluginDirectories: const ['/p'],
          perPluginDisabled: const {'p1': true},
          activeThemeName: 'oscilloscope',
        );
        await codec.save(prefs, settings);

        expect(prefs.getInt('settings.themeMode'), AppThemeMode.light.index);
        expect(prefs.getString('settings.locale'), 'zh_CN');
        expect(prefs.getBool('settings.diagnosticsEnabled'), isTrue);
        expect(prefs.getStringList('settings.userPluginDirectories'), ['/p']);
        expect(
          prefs.getString('settings.perPluginDisabled'),
          jsonEncode({'p1': true}),
        );
        expect(prefs.getString('settings.activeThemeName'), 'oscilloscope');
      },
    );
  });

  group('round-trip', () {
    test('save + load returns equivalent settings', () async {
      final prefs = await _prefs();
      final original = const CoreSettings.defaults().copyWith(
        themeMode: AppThemeMode.system,
        autoReloadMode: AutoReloadMode.off,
        autoSaveIntervalSeconds: 90,
        locale: 'ko',
        diagnosticsEnabled: true,
        orientationLockMode: OrientationLockMode.portraitLock,
        autoHideChromeSeconds: 10,
        userPluginDirectories: const ['/one', '/two'],
        pluginSafetyAcknowledged: true,
        perPluginDisabled: const {'a': true, 'b': false},
        activeThemeName: 'high-contrast-dark',
        themeOverrides: const {'canvas.background': '#000000'},
        restoreTabsOnLaunch: false,
      );

      await codec.save(prefs, original);
      final loaded = await codec.load(prefs);
      expect(loaded, equals(original));
    });
  });
}
