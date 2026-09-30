// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color;

/// On-disk representation of a `.crux-theme.json` pack.
///
/// A pack is the JSON-friendly side of a [CruxColorTheme]: it carries
/// the same identity ([id], [displayName], [brightness]) plus the same
/// token table, but as a value type round-trippable through
/// `ThemePackCodec` and `ThemePackService`.
///
/// The pack also records an optional [sourceUri] — typically the
/// `file://` path the pack was loaded from, or an `asset:` URI for
/// built-in presets. The source uri is not part of the JSON document;
/// it is metadata the service layer attaches when reading from disk.
@immutable
class ThemePack {
  /// Creates a pack from a fully-resolved token table.
  ///
  /// The constructor freezes a defensive copy of [tokens] so later
  /// caller-side mutation never bleeds in.
  ThemePack({
    required this.id,
    required this.displayName,
    required this.brightness,
    required Map<String, Map<String, Color>> tokens,
    this.sourceUri,
  }) : tokens = _freeze(tokens);

  /// Stable id. Drives filename when saving (`<id>.crux-theme.json`)
  /// and keys the active-theme record in user settings.
  final String id;

  /// Human-readable label.
  final String displayName;

  /// Base brightness for fallback resolution.
  final Brightness brightness;

  /// Token map keyed by `category.id → token.id → Color`. Unmodifiable.
  final Map<String, Map<String, Color>> tokens;

  /// Optional metadata: where this pack came from. Set by the loader
  /// (e.g. the path read from). Not serialized to JSON.
  final Uri? sourceUri;

  /// Returns the color for `(categoryId, tokenId)`, or `null` if either
  /// the category or the token is absent.
  Color? color(String categoryId, String tokenId) =>
      tokens[categoryId]?[tokenId];

  /// Returns the color for `(categoryId, tokenId)`, falling back to
  /// [fallback] if either is absent.
  Color colorOr(String categoryId, String tokenId, Color fallback) =>
      tokens[categoryId]?[tokenId] ?? fallback;

  /// Returns true if `(categoryId, tokenId)` has an explicit color in
  /// this pack.
  bool hasToken(String categoryId, String tokenId) =>
      tokens[categoryId]?.containsKey(tokenId) ?? false;

  /// Returns the pack as a [CruxColorTheme] suitable for activation.
  CruxColorTheme toTheme() => CruxColorTheme(
    id: id,
    displayName: displayName,
    brightness: brightness,
    tokens: tokens,
  );

  /// Returns a small header summary suitable for list views without
  /// loading the full token table.
  ThemePackHeader toHeader() => ThemePackHeader(
    id: id,
    displayName: displayName,
    brightness: brightness,
    sourceUri: sourceUri,
  );

  /// Returns a copy with the listed fields replaced. Passing a `tokens`
  /// map fully replaces the previous token table.
  ThemePack copyWith({
    String? id,
    String? displayName,
    Brightness? brightness,
    Map<String, Map<String, Color>>? tokens,
    Uri? sourceUri,
  }) {
    return ThemePack(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      brightness: brightness ?? this.brightness,
      tokens: tokens ?? _deepMutable(this.tokens),
      sourceUri: sourceUri ?? this.sourceUri,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ThemePack) return false;
    if (other.id != id) return false;
    if (other.displayName != displayName) return false;
    if (other.brightness != brightness) return false;
    if (other.sourceUri != sourceUri) return false;
    if (other.tokens.length != tokens.length) return false;
    for (final entry in tokens.entries) {
      final otherCategory = other.tokens[entry.key];
      if (otherCategory == null) return false;
      if (!mapEquals(otherCategory, entry.value)) return false;
    }
    return true;
  }

  /// Cached: `ThemePack` is an `@immutable` value type whose hash sorts
  /// every key list and allocates two lists per category. The value can
  /// never change, so compute it at most once.
  @override
  late final int hashCode = _computeHashCode();

  int _computeHashCode() {
    final categoryHashes = <int>[];
    final sortedKeys = tokens.keys.toList()..sort();
    for (final key in sortedKeys) {
      final inner = tokens[key]!;
      final innerKeys = inner.keys.toList()..sort();
      final innerHashes = <int>[];
      for (final ik in innerKeys) {
        innerHashes.add(Object.hash(ik, inner[ik]));
      }
      categoryHashes.add(Object.hash(key, Object.hashAll(innerHashes)));
    }
    return Object.hash(
      id,
      displayName,
      brightness,
      sourceUri,
      Object.hashAll(categoryHashes),
    );
  }

  @override
  String toString() => 'ThemePack($id, ${brightness.name})';

  static Map<String, Map<String, Color>> _freeze(
    Map<String, Map<String, Color>> source,
  ) {
    final frozen = <String, Map<String, Color>>{};
    for (final entry in source.entries) {
      frozen[entry.key] = Map<String, Color>.unmodifiable(entry.value);
    }
    return Map<String, Map<String, Color>>.unmodifiable(frozen);
  }

  static Map<String, Map<String, Color>> _deepMutable(
    Map<String, Map<String, Color>> source,
  ) {
    return {
      for (final entry in source.entries)
        entry.key: Map<String, Color>.from(entry.value),
    };
  }
}

/// Lightweight pack summary returned by `ThemePackService.list`.
///
/// Holds only the metadata needed to render a row in a preset picker.
/// Full token-table load happens lazily when the user activates a pack.
@immutable
class ThemePackHeader {
  /// Creates a header. Typically called from the service layer rather
  /// than directly by consumers.
  const ThemePackHeader({
    required this.id,
    required this.displayName,
    required this.brightness,
    this.sourceUri,
  });

  /// Stable id from the underlying pack document.
  final String id;

  /// Human-readable label.
  final String displayName;

  /// Base brightness.
  final Brightness brightness;

  /// Where this header was extracted from. `null` for built-in presets
  /// returned without a disk source.
  final Uri? sourceUri;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemePackHeader &&
        other.id == id &&
        other.displayName == displayName &&
        other.brightness == brightness &&
        other.sourceUri == sourceUri;
  }

  @override
  int get hashCode => Object.hash(id, displayName, brightness, sourceUri);

  @override
  String toString() => 'ThemePackHeader($id, ${brightness.name})';
}

/// Result of `ThemePackService.validate`.
///
/// Holds either the decoded [pack] on success, or an ordered list of
/// human-readable [errors] describing why validation failed. The two
/// fields are mutually exclusive: a successful validation has [pack]
/// set and [errors] empty; a failed validation has [pack] null and one
/// or more [errors].
@immutable
class ThemePackValidation {
  /// Success result wrapping the decoded pack.
  const ThemePackValidation.ok(ThemePack this.pack) : errors = const [];

  /// Failure result with one or more errors.
  ThemePackValidation.failed(List<String> errors)
    : pack = null,
      errors = List<String>.unmodifiable(errors);

  /// Decoded pack on success; `null` on failure.
  final ThemePack? pack;

  /// Error messages on failure; empty on success.
  final List<String> errors;

  /// Convenience: `true` when validation succeeded.
  bool get isValid => pack != null;
}
