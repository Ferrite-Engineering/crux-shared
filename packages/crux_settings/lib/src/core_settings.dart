// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/src/app_theme_mode.dart';
import 'package:crux_settings/src/auto_reload_mode.dart';
import 'package:crux_settings/src/orientation_lock_mode.dart';
import 'package:meta/meta.dart';

/// The cross-suite shared subset of application settings.
///
/// Every Crux product composes a
/// `CoreSettings` into its own per-product `AppSettings`, alongside any
/// product-specific fields. The codec for this model reads and writes the
/// `settings.*` `SharedPreferences` key namespace, which is stable across
/// releases so a user's preferences survive upgrades.
///
/// All fields are immutable. Use [copyWith] for updates.
@immutable
class CoreSettings {
  /// Creates a fully-specified [CoreSettings]. Use [CoreSettings.defaults]
  /// or [copyWith] to construct values with the standard defaults.
  const CoreSettings({
    required this.themeMode,
    required this.autoReloadMode,
    required this.autoSaveIntervalSeconds,
    required this.locale,
    required this.diagnosticsEnabled,
    required this.orientationLockMode,
    required this.autoHideChromeSeconds,
    required this.userPluginDirectories,
    required this.pluginSafetyAcknowledged,
    required this.pluginLoadingDisabled,
    required this.perPluginDisabled,
    required this.activeThemeName,
    required this.themeOverrides,
    required this.restoreTabsOnLaunch,
  });

  /// The standard set of defaults, matching WaveCrux's historical defaults.
  /// Other products may construct their own defaults via [copyWith] when
  /// their preferred values differ.
  const CoreSettings.defaults()
    : themeMode = AppThemeMode.dark,
      autoReloadMode = AutoReloadMode.prompt,
      autoSaveIntervalSeconds = 60,
      locale = 'en',
      diagnosticsEnabled = false,
      orientationLockMode = OrientationLockMode.auto,
      autoHideChromeSeconds = 3,
      userPluginDirectories = const <String>[],
      pluginSafetyAcknowledged = false,
      pluginLoadingDisabled = false,
      perPluginDisabled = const <String, bool>{},
      // Suite-neutral default. Beta users have the retired
      // 'wavecrux-dark' / 'wavecrux-light' ids persisted; read paths
      // migrate them via crux_theme's `migratePresetId`.
      activeThemeName = 'crux-dark',
      themeOverrides = const <String, String>{},
      restoreTabsOnLaunch = true;

  /// Color theme preference (system / light / dark).
  final AppThemeMode themeMode;

  /// How to respond when the active source file changes on disk.
  final AutoReloadMode autoReloadMode;

  /// Auto-save interval for session/workspace state, in seconds. Range 10–600.
  final int autoSaveIntervalSeconds;

  /// Active UI locale (BCP-47 code, e.g. `en`, `zh_CN`).
  final String locale;

  /// Whether the diagnostics surfaces are enabled in release builds.
  final bool diagnosticsEnabled;

  /// Device-orientation preference. Honored on mobile; ignored on desktop.
  final OrientationLockMode orientationLockMode;

  /// How long (seconds) chrome stays visible before auto-hiding, when
  /// auto-hide is active. Range 1–30.
  final int autoHideChromeSeconds;

  /// User-supplied directories scanned for native plugins.
  final List<String> userPluginDirectories;

  /// Whether the first-load safety acknowledgment for native plugins has
  /// been dismissed by the user.
  final bool pluginSafetyAcknowledged;

  /// Master kill-switch: when true, the plugin loader skips its directory
  /// scan entirely.
  final bool pluginLoadingDisabled;

  /// Per-plugin disable toggles (keyed by plugin id).
  final Map<String, bool> perPluginDisabled;

  /// Name of the active color theme pack (e.g. `crux-dark`,
  /// `solarized-dark`).
  final String activeThemeName;

  /// Quick color-token overrides layered on top of the active theme pack.
  final Map<String, String> themeOverrides;

  /// Whether to restore the workspace (open tabs / panes) on next launch.
  final bool restoreTabsOnLaunch;

  /// Returns a copy with overridden fields. Omitted fields retain their
  /// current values.
  CoreSettings copyWith({
    AppThemeMode? themeMode,
    AutoReloadMode? autoReloadMode,
    int? autoSaveIntervalSeconds,
    String? locale,
    bool? diagnosticsEnabled,
    OrientationLockMode? orientationLockMode,
    int? autoHideChromeSeconds,
    List<String>? userPluginDirectories,
    bool? pluginSafetyAcknowledged,
    bool? pluginLoadingDisabled,
    Map<String, bool>? perPluginDisabled,
    String? activeThemeName,
    Map<String, String>? themeOverrides,
    bool? restoreTabsOnLaunch,
  }) {
    return CoreSettings(
      themeMode: themeMode ?? this.themeMode,
      autoReloadMode: autoReloadMode ?? this.autoReloadMode,
      autoSaveIntervalSeconds:
          autoSaveIntervalSeconds ?? this.autoSaveIntervalSeconds,
      locale: locale ?? this.locale,
      diagnosticsEnabled: diagnosticsEnabled ?? this.diagnosticsEnabled,
      orientationLockMode: orientationLockMode ?? this.orientationLockMode,
      autoHideChromeSeconds:
          autoHideChromeSeconds ?? this.autoHideChromeSeconds,
      userPluginDirectories:
          userPluginDirectories ?? this.userPluginDirectories,
      pluginSafetyAcknowledged:
          pluginSafetyAcknowledged ?? this.pluginSafetyAcknowledged,
      pluginLoadingDisabled:
          pluginLoadingDisabled ?? this.pluginLoadingDisabled,
      perPluginDisabled: perPluginDisabled ?? this.perPluginDisabled,
      activeThemeName: activeThemeName ?? this.activeThemeName,
      themeOverrides: themeOverrides ?? this.themeOverrides,
      restoreTabsOnLaunch: restoreTabsOnLaunch ?? this.restoreTabsOnLaunch,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CoreSettings) return false;
    if (other.themeMode != themeMode) return false;
    if (other.autoReloadMode != autoReloadMode) return false;
    if (other.autoSaveIntervalSeconds != autoSaveIntervalSeconds) return false;
    if (other.locale != locale) return false;
    if (other.diagnosticsEnabled != diagnosticsEnabled) return false;
    if (other.orientationLockMode != orientationLockMode) return false;
    if (other.autoHideChromeSeconds != autoHideChromeSeconds) return false;
    if (!_listEquals(other.userPluginDirectories, userPluginDirectories)) {
      return false;
    }
    if (other.pluginSafetyAcknowledged != pluginSafetyAcknowledged) {
      return false;
    }
    if (other.pluginLoadingDisabled != pluginLoadingDisabled) return false;
    if (!_mapEquals(other.perPluginDisabled, perPluginDisabled)) return false;
    if (other.activeThemeName != activeThemeName) return false;
    if (!_mapEquals(other.themeOverrides, themeOverrides)) return false;
    if (other.restoreTabsOnLaunch != restoreTabsOnLaunch) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    autoReloadMode,
    autoSaveIntervalSeconds,
    locale,
    diagnosticsEnabled,
    orientationLockMode,
    autoHideChromeSeconds,
    Object.hashAll(userPluginDirectories),
    pluginSafetyAcknowledged,
    pluginLoadingDisabled,
    // Hash entries as key+value pairs: hashing keys alone would give two
    // settings objects that differ only in a toggle's value (or an
    // override's color) equal hashes while == reports them unequal.
    Object.hashAllUnordered(
      perPluginDisabled.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    activeThemeName,
    Object.hashAllUnordered(
      themeOverrides.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    restoreTabsOnLaunch,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
