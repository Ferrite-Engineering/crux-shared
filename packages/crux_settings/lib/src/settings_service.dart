// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/src/settings_codec.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Generic settings service that ties a [SettingsCodec] to
/// `SharedPreferences`.
///
/// Each product creates one instance with its own product-specific codec:
/// ```dart
/// final settingsService = SettingsService<AppSettings>(
///   const WaveCruxSettingsCodec(),
/// );
/// final settings = await settingsService.load();
/// await settingsService.save(settings.copyWith(/* ... */));
/// ```
///
/// The service is the only place that calls `SharedPreferences.getInstance()`;
/// codecs receive the resolved [SharedPreferences] handle so they never have
/// to deal with the async-singleton dance.
@immutable
class SettingsService<T> {
  /// Creates a service backed by [codec].
  ///
  /// In tests, pass [prefsOverride] to bypass the platform plugin entirely
  /// — every call to [load] / [save] uses the supplied instance instead of
  /// `SharedPreferences.getInstance()`.
  const SettingsService(this.codec, {this.prefsOverride});

  /// The codec that defines how [T] is serialized to and from preferences.
  final SettingsCodec<T> codec;

  /// Test-only `SharedPreferences` instance. When null, the service falls
  /// back to `SharedPreferences.getInstance()`.
  final SharedPreferences? prefsOverride;

  /// Loads persisted settings. Missing keys fall back to the codec's
  /// per-field defaults.
  Future<T> load() async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    return await codec.load(prefs);
  }

  /// Persists [settings].
  Future<void> save(T settings) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    await codec.save(prefs, settings);
  }
}
