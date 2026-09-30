// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite shared settings infrastructure for the EDACrux suite.
///
/// Exports the shared `CoreSettings` model + its three supporting enums
/// (`AppThemeMode`, `AutoReloadMode`, `OrientationLockMode`), the abstract
/// `SettingsCodec<T>` interface, the concrete `CoreSettingsCodec`, and the
/// generic `SettingsService<T>` that ties a codec to `SharedPreferences`.
///
/// See the package README for the canonical usage pattern.
library;

export 'src/app_theme_mode.dart';
export 'src/auto_reload_mode.dart';
export 'src/core_settings.dart';
export 'src/core_settings_codec.dart';
export 'src/orientation_lock_mode.dart';
export 'src/settings_codec.dart';
export 'src/settings_service.dart';
