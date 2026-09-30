// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/presets/builtin_presets.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Synchronous notifier that holds the active [CruxColorTheme].
///
/// Each product overrides [cruxColorThemeProvider] at startup with an
/// instance of [CruxColorThemeNotifier] configured with the desired
/// initial theme:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     cruxColorThemeProvider.overrideWith(
///       () => CruxColorThemeNotifier(
///         initial: builtinPresets()[cruxDarkPresetId]!,
///       ),
///     ),
///   ],
///   child: const MyApp(),
/// )
/// ```
///
/// Mutations:
/// - [activate] replaces the active theme outright (e.g. preset switch).
/// - [applyOverrides] layers a sparse override map on top of the
///   current theme. Useful for the Settings → Appearance quick-edit
///   panel where the user nudges one or two colors without swapping
///   the whole preset.
/// - [reset] returns to the [initial] theme.
///
/// Persistence is the host product's responsibility: a typical adopter
/// wraps this notifier with a `ref.listen` that calls
/// `ThemePackService.save` whenever the state changes, and supplies
/// an initial theme loaded from disk at startup. The notifier itself
/// stays in-memory only.
class CruxColorThemeNotifier extends Notifier<CruxColorTheme> {
  /// Creates a notifier with [initial] as the starting theme.
  CruxColorThemeNotifier({required this.initial});

  /// The theme returned by [build] on first read and restored by
  /// [reset]. Captured at construction so overrides do not leak into
  /// the reset target.
  final CruxColorTheme initial;

  @override
  CruxColorTheme build() => initial;

  /// Replaces the active theme.
  ///
  /// Conventional Notifier-mutation shape — the matching crux-shared
  /// notifiers also expose action-named methods rather than setters.
  // ignore: use_setters_to_change_properties
  void activate(CruxColorTheme theme) {
    state = theme;
  }

  /// Layers sparse [overrides] on top of the current theme. Keys are
  /// dotted `<category>.<token>` ids; malformed keys are silently
  /// ignored. Returns the same instance when [overrides] is empty.
  void applyOverrides(Map<String, Color> overrides) {
    if (overrides.isEmpty) return;
    state = state.mergeTokens(overrides);
  }

  /// Restores the [initial] theme passed at construction.
  void reset() {
    state = initial;
  }
}

/// Provider for the active [CruxColorTheme]. Consumers must
/// `overrideWith` a [CruxColorThemeNotifier] tuned for their app at
/// startup; the default factory uses [defaultBuiltinPreset] so that an
/// un-overridden test or a quick spike still gets a working theme.
final NotifierProvider<CruxColorThemeNotifier, CruxColorTheme>
cruxColorThemeProvider =
    NotifierProvider<CruxColorThemeNotifier, CruxColorTheme>(
      () => CruxColorThemeNotifier(initial: defaultBuiltinPreset()),
    );
