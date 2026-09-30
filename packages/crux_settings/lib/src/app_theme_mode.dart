// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The application color theme preference.
///
/// Pure-Dart enum (no Flutter imports) so `CoreSettings` stays pure-Dart at
/// the domain level. Each product converts to its Flutter `ThemeMode`
/// equivalent at the presentation layer.
enum AppThemeMode {
  /// Follow the host OS / system preference.
  system,

  /// Always use the light theme.
  light,

  /// Always use the dark theme (suite-wide default for engineering tools).
  dark,
}
