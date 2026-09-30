// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_settings/src/app_theme_mode.dart';
import 'package:crux_settings/src/auto_reload_mode.dart';
import 'package:crux_settings/src/core_settings.dart';
import 'package:crux_settings/src/orientation_lock_mode.dart';
import 'package:crux_settings/src/settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Concrete codec for [CoreSettings] using `SharedPreferences`.
///
/// Keys live under the `settings.*` namespace, which is stable across
/// releases: every product reads and writes the same key for the same
/// setting, so a user's preferences survive upgrades.
///
/// [save] writes the full settings record — all fourteen keys — on every
/// call, rather than diffing against the stored values. A `const` stateless
/// codec has no previous state to diff against, and settings changes are
/// click-driven, so the cost is irrelevant in practice. Callers wiring a
/// *continuous* control (a slider's `onChanged`, a live-updating text field)
/// straight to [save] must debounce it themselves.
///
/// Per-product codecs typically delegate to this codec for the
/// [CoreSettings] portion of their settings model:
/// ```dart
/// class WaveCruxSettingsCodec implements SettingsCodec<AppSettings> {
///   @override
///   Future<AppSettings> load(SharedPreferences prefs) async {
///     final core = await const CoreSettingsCodec().load(prefs);
///     // ... read wavecrux-specific fields from prefs
///     return AppSettings(core: core, ...);
///   }
///   @override
///   Future<void> save(SharedPreferences prefs, AppSettings settings) async {
///     await const CoreSettingsCodec().save(prefs, settings.core);
///     // ... write wavecrux-specific fields to prefs
///   }
/// }
/// ```
class CoreSettingsCodec implements SettingsCodec<CoreSettings> {
  /// Const constructor — codec is stateless.
  const CoreSettingsCodec();

  static const _kThemeMode = 'settings.themeMode';
  static const _kAutoReloadMode = 'settings.autoReloadMode';
  static const _kAutoSaveInterval = 'settings.autoSaveIntervalSeconds';
  static const _kLocale = 'settings.locale';
  static const _kDiagnosticsEnabled = 'settings.diagnosticsEnabled';
  static const _kOrientationLockMode = 'settings.orientationLockMode';
  static const _kAutoHideChromeSeconds = 'settings.autoHideChromeSeconds';
  static const _kUserPluginDirectories = 'settings.userPluginDirectories';
  static const _kPluginSafetyAcknowledged = 'settings.pluginSafetyAcknowledged';
  static const _kPluginLoadingDisabled = 'settings.pluginLoadingDisabled';
  static const _kPerPluginDisabled = 'settings.perPluginDisabled';
  static const _kActiveThemeName = 'settings.activeThemeName';
  static const _kThemeOverrides = 'settings.themeOverrides';
  static const _kRestoreTabsOnLaunch = 'settings.restoreTabsOnLaunch';

  @override
  Future<CoreSettings> load(SharedPreferences prefs) async {
    const defaults = CoreSettings.defaults();
    return CoreSettings(
      themeMode: _enumOf(
        AppThemeMode.values,
        prefs.getInt(_kThemeMode),
        defaults.themeMode,
      ),
      autoReloadMode: _enumOf(
        AutoReloadMode.values,
        prefs.getInt(_kAutoReloadMode),
        defaults.autoReloadMode,
      ),
      autoSaveIntervalSeconds:
          (prefs.getInt(_kAutoSaveInterval) ?? defaults.autoSaveIntervalSeconds)
              .clamp(10, 600),
      locale: prefs.getString(_kLocale) ?? defaults.locale,
      diagnosticsEnabled:
          prefs.getBool(_kDiagnosticsEnabled) ?? defaults.diagnosticsEnabled,
      orientationLockMode: _enumOf(
        OrientationLockMode.values,
        prefs.getInt(_kOrientationLockMode),
        defaults.orientationLockMode,
      ),
      autoHideChromeSeconds:
          (prefs.getInt(_kAutoHideChromeSeconds) ??
                  defaults.autoHideChromeSeconds)
              .clamp(1, 30),
      userPluginDirectories:
          prefs.getStringList(_kUserPluginDirectories) ??
          defaults.userPluginDirectories,
      pluginSafetyAcknowledged:
          prefs.getBool(_kPluginSafetyAcknowledged) ??
          defaults.pluginSafetyAcknowledged,
      pluginLoadingDisabled:
          prefs.getBool(_kPluginLoadingDisabled) ??
          defaults.pluginLoadingDisabled,
      perPluginDisabled: _decodePerPluginDisabled(
        prefs.getString(_kPerPluginDisabled),
      ),
      activeThemeName:
          prefs.getString(_kActiveThemeName) ?? defaults.activeThemeName,
      themeOverrides: _decodeThemeOverrides(
        prefs.getString(_kThemeOverrides),
      ),
      restoreTabsOnLaunch:
          prefs.getBool(_kRestoreTabsOnLaunch) ?? defaults.restoreTabsOnLaunch,
    );
  }

  @override
  Future<void> save(SharedPreferences prefs, CoreSettings settings) async {
    await Future.wait([
      prefs.setInt(_kThemeMode, settings.themeMode.index),
      prefs.setInt(_kAutoReloadMode, settings.autoReloadMode.index),
      prefs.setInt(_kAutoSaveInterval, settings.autoSaveIntervalSeconds),
      prefs.setString(_kLocale, settings.locale),
      prefs.setBool(_kDiagnosticsEnabled, settings.diagnosticsEnabled),
      prefs.setInt(_kOrientationLockMode, settings.orientationLockMode.index),
      prefs.setInt(_kAutoHideChromeSeconds, settings.autoHideChromeSeconds),
      prefs.setStringList(
        _kUserPluginDirectories,
        settings.userPluginDirectories,
      ),
      prefs.setBool(
        _kPluginSafetyAcknowledged,
        settings.pluginSafetyAcknowledged,
      ),
      prefs.setBool(_kPluginLoadingDisabled, settings.pluginLoadingDisabled),
      prefs.setString(
        _kPerPluginDisabled,
        jsonEncode(settings.perPluginDisabled),
      ),
      prefs.setString(_kActiveThemeName, settings.activeThemeName),
      prefs.setString(_kThemeOverrides, jsonEncode(settings.themeOverrides)),
      prefs.setBool(_kRestoreTabsOnLaunch, settings.restoreTabsOnLaunch),
    ]);
  }

  /// Returns `values[index]` when [index] is valid; otherwise [fallback].
  T _enumOf<T>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  Map<String, String> _decodeThemeOverrides(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String && value is String) {
          out[key] = value;
        }
      });
      return out;
    } on FormatException {
      return const <String, String>{};
    }
  }

  Map<String, bool> _decodePerPluginDisabled(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, bool>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, bool>{};
      final out = <String, bool>{};
      decoded.forEach((key, value) {
        if (key is String && value is bool) {
          out[key] = value;
        }
      });
      return out;
    } on FormatException {
      return const <String, bool>{};
    }
  }
}
