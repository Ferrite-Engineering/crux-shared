// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/preset_token_overlay.dart';
import 'package:crux_theme/src/theme_token_category.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

/// Runtime registry of token categories.
///
/// Each Crux product registers its own [ThemeTokenCategory] set at
/// startup via [registerCategory]. The registry surfaces the
/// aggregated schema to the Settings UI (preset cards, swatch grids)
/// and provides fallback-resolved color lookup on top of any
/// [CruxColorTheme] via [resolve] — callers who want descriptor
/// brightness defaults to kick in when a token is absent route
/// through the registry rather than reading the theme's token map
/// directly.
///
/// The registry is a process-wide singleton — there is one schema per
/// app, gathered at startup. Tests reset it via [resetForTesting].
class ThemeRegistry {
  ThemeRegistry._();

  /// The process-wide singleton.
  static final ThemeRegistry instance = ThemeRegistry._();

  final Map<String, ThemeTokenCategory> _categories =
      <String, ThemeTokenCategory>{};

  final Map<String, PresetTokenOverlay> _presetOverlays =
      <String, PresetTokenOverlay>{};

  /// Monotonic counter bumped on every mutation. `builtinPresets()`
  /// uses it to invalidate its composed-preset cache without having to
  /// diff the overlay table.
  int _revision = 0;

  /// Cached unmodifiable views, invalidated by [_revision]. Both
  /// `registeredCategories` and `allRegisteredTokens` are read during
  /// `build()` (e.g. `PresetPreview._resolveTokens`), so allocating a
  /// fresh unmodifiable collection per access showed up as per-frame
  /// garbage.
  List<ThemeTokenCategory>? _cachedCategories;
  int _cachedCategoriesRevision = -1;
  Map<String, ThemeTokenDescriptor>? _cachedTokens;
  int _cachedTokensRevision = -1;

  /// Current mutation revision. Callers that cache derived state keyed
  /// on the registry's contents compare this instead of the contents.
  int get revision => _revision;

  /// Registers [category]. The category's [ThemeTokenCategory.id] must
  /// be non-empty.
  ///
  /// Registration is **idempotent for an identical category**: calling
  /// this twice with equal categories is a no-op. That matters because
  /// the registry is process-wide while product startup is not — a
  /// second window, a re-run of `bootstrap()` in the same isolate, or a
  /// widget test that boots the app twice would otherwise crash on a
  /// duplicate id.
  ///
  /// A *conflicting* re-registration — same id, different token set —
  /// is still a hard [StateError], because that is a genuine
  /// programming error (two products claiming one category id, or a
  /// typo) and silently keeping one of the two would make the Settings
  /// editor disagree with the renderer.
  void registerCategory(ThemeTokenCategory category) {
    if (category.id.isEmpty) {
      throw ArgumentError.value(
        category.id,
        'category.id',
        'ThemeTokenCategory.id must be non-empty.',
      );
    }
    final existing = _categories[category.id];
    if (existing != null) {
      if (existing == category) return;
      throw StateError(
        'ThemeTokenCategory "${category.id}" is already registered with a '
        'different definition. Two products must not claim the same '
        'category id.',
      );
    }
    _categories[category.id] = category;
    _revision++;
  }

  /// Registers a [PresetTokenOverlay] contributing product-specific
  /// token values to the shared built-in presets.
  ///
  /// Idempotent on the same terms as [registerCategory]: re-registering
  /// an equal overlay is a no-op, a conflicting one throws.
  void registerPresetOverlay(PresetTokenOverlay overlay) {
    if (overlay.categoryId.isEmpty) {
      throw ArgumentError.value(
        overlay.categoryId,
        'overlay.categoryId',
        'PresetTokenOverlay.categoryId must be non-empty.',
      );
    }
    final existing = _presetOverlays[overlay.categoryId];
    if (existing != null) {
      if (existing == overlay) return;
      throw StateError(
        'PresetTokenOverlay for category "${overlay.categoryId}" is already '
        'registered with different values.',
      );
    }
    _presetOverlays[overlay.categoryId] = overlay;
    _revision++;
  }

  /// All registered preset overlays, in registration order.
  Iterable<PresetTokenOverlay> get registeredPresetOverlays =>
      _presetOverlays.values;

  /// Returns true if a category with [categoryId] has been registered.
  bool hasCategory(String categoryId) => _categories.containsKey(categoryId);

  /// Returns the registered category for [categoryId], or `null` if no
  /// category has been registered with that id.
  ThemeTokenCategory? category(String categoryId) => _categories[categoryId];

  /// All registered categories, in registration order.
  ///
  /// The returned view is cached until the next registration, so
  /// build-time callers (`PresetPreview`) do not allocate per frame.
  List<ThemeTokenCategory> get registeredCategories {
    if (_cachedCategoriesRevision != _revision || _cachedCategories == null) {
      _cachedCategories = List<ThemeTokenCategory>.unmodifiable(
        _categories.values,
      );
      _cachedCategoriesRevision = _revision;
    }
    return _cachedCategories!;
  }

  /// All registered descriptors keyed by the dotted `<category>.<token>`
  /// id. Useful for the Settings UI to render a flat list of every
  /// themable color in the app. Cached until the next registration.
  Map<String, ThemeTokenDescriptor> get allRegisteredTokens {
    if (_cachedTokensRevision != _revision || _cachedTokens == null) {
      final flat = <String, ThemeTokenDescriptor>{};
      for (final category in _categories.values) {
        for (final descriptor in category.tokens) {
          flat[CruxColorTheme.dottedId(category.id, descriptor.id)] =
              descriptor;
        }
      }
      _cachedTokens = Map<String, ThemeTokenDescriptor>.unmodifiable(flat);
      _cachedTokensRevision = _revision;
    }
    return _cachedTokens!;
  }

  /// Resolves `(categoryId, tokenId)` against [theme], substituting the
  /// registered descriptor's brightness-appropriate default if the
  /// theme omits the token. Returns `null` if the category is not
  /// registered and the theme also has no value.
  ///
  /// Use this in widget code instead of [CruxColorTheme.color] when
  /// you want the engine's descriptor-default fallback (typical for
  /// rendering chrome that uses Material 3 defaults when a theme pack
  /// is silent on a token).
  Color? resolve(CruxColorTheme theme, String categoryId, String tokenId) {
    final explicit = theme.color(categoryId, tokenId);
    if (explicit != null) return explicit;
    final descriptor = _categories[categoryId]?.descriptor(tokenId);
    return descriptor?.defaultFor(theme.brightness);
  }

  /// Layers [overrides] on top of [base] and returns the resulting
  /// theme. Keys are dotted `<category>.<token>` ids; malformed keys
  /// are silently ignored. Convenience over [CruxColorTheme.mergeTokens]
  /// kept on the registry so call sites for both have a single import.
  static CruxColorTheme merge(
    CruxColorTheme base,
    Map<String, Color> overrides,
  ) {
    return base.mergeTokens(overrides);
  }

  /// Test-only: clears the registry so each test starts from a clean
  /// slate. Throws [StateError] outside debug mode to avoid accidental
  /// production resets.
  @visibleForTesting
  void resetForTesting() {
    if (!kDebugMode) {
      throw StateError(
        'ThemeRegistry.resetForTesting must not be called in release mode.',
      );
    }
    _categories.clear();
    _presetOverlays.clear();
    _revision++;
  }
}
