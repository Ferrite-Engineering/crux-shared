// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color;

/// An immutable, schema-free color theme keyed by named tokens.
///
/// A theme is a flat map of `category → token → color` entries plus an
/// [id], a [displayName], and a base [brightness]. The package never
/// hard-codes a category id or a token id; every product registers its
/// own `ThemeTokenCategory` set with the runtime registry. A theme that
/// omits a token falls back to the descriptor's default for the active
/// brightness — fallback resolution is performed by the registry, not
/// here.
@immutable
class CruxColorTheme {
  /// Creates a theme with the given identity and token table.
  ///
  /// [id] must be non-empty and unique within the user's installed set
  /// (built-in preset ids are reserved). The constructor freezes a
  /// defensive copy of [tokens] so later mutation of the caller's map
  /// can't observe through to this instance.
  CruxColorTheme({
    required this.id,
    required this.displayName,
    required this.brightness,
    required Map<String, Map<String, Color>> tokens,
  }) : tokens = _freeze(tokens);

  /// Internal constructor that adopts [tokens] **without** copying it
  /// into unmodifiable wrappers.
  ///
  /// Only for callers that just built the map themselves and provably
  /// retain no reference to it — today that is
  /// `CruxThemeExtension.lerp`, which runs on every frame of a
  /// MaterialApp theme transition and was paying for the full
  /// defensive copy a second time on top of the table it had just
  /// allocated. Passing a caller-owned map through here would break
  /// the immutability contract, so it is marked [internal] — a
  /// consumer outside `crux_theme` that calls it gets an analyzer
  /// diagnostic.
  @internal
  CruxColorTheme.internalUnsafe({
    required this.id,
    required this.displayName,
    required this.brightness,
    required this.tokens,
  });

  /// Stable id. Survives across launches and is the key callers use to
  /// re-activate a previously selected preset or imported pack.
  final String id;

  /// Human-readable label shown in the Settings → Appearance editor.
  final String displayName;

  /// Base brightness. Controls which fallback default the registry
  /// substitutes when a token is absent from [tokens], and also
  /// determines the `ThemeData.brightness` consumers should set.
  final Brightness brightness;

  /// Token map keyed by `category.id → token.id → Color`. Empty
  /// categories and missing tokens are both legal; the registry
  /// resolves the latter to the descriptor's brightness-appropriate
  /// default.
  ///
  /// The map and every inner map are unmodifiable.
  final Map<String, Map<String, Color>> tokens;

  /// Returns the color for `(categoryId, tokenId)`, or `null` if either
  /// the category or the token is absent. Callers that want descriptor
  /// fallback should resolve through the registry.
  Color? color(String categoryId, String tokenId) =>
      tokens[categoryId]?[tokenId];

  /// Returns the color for `(categoryId, tokenId)`, falling back to
  /// [fallback] if either is absent.
  Color colorOr(String categoryId, String tokenId, Color fallback) =>
      tokens[categoryId]?[tokenId] ?? fallback;

  /// Returns true if `(categoryId, tokenId)` has an explicit color in
  /// this theme.
  bool hasToken(String categoryId, String tokenId) =>
      tokens[categoryId]?.containsKey(tokenId) ?? false;

  /// Returns a copy with the listed fields replaced. Passing a `tokens`
  /// map fully replaces the previous token table; use [mergeTokens] to
  /// layer changes on top.
  CruxColorTheme copyWith({
    String? id,
    String? displayName,
    Brightness? brightness,
    Map<String, Map<String, Color>>? tokens,
  }) {
    return CruxColorTheme(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      brightness: brightness ?? this.brightness,
      tokens: tokens ?? _deepMutable(this.tokens),
    );
  }

  /// Returns a copy with the entries in [overrides] applied on top of
  /// the current token table. Each entry's key is the
  /// `<category>.<token>` dotted id; the first '.' separator splits.
  /// Unknown keys (no '.') are ignored.
  CruxColorTheme mergeTokens(Map<String, Color> overrides) {
    if (overrides.isEmpty) return this;
    final mutable = _deepMutable(tokens);
    for (final entry in overrides.entries) {
      final dot = entry.key.indexOf('.');
      if (dot <= 0 || dot == entry.key.length - 1) continue;
      final category = entry.key.substring(0, dot);
      final token = entry.key.substring(dot + 1);
      final bucket = mutable.putIfAbsent(category, () => <String, Color>{});
      bucket[token] = entry.value;
    }
    return copyWith(tokens: mutable);
  }

  /// Returns the dotted id form (`<category>.<token>`) for a token.
  ///
  /// Pure helper kept on the value type so callers don't reach for a
  /// utility namespace just to assemble keys.
  static String dottedId(String categoryId, String tokenId) =>
      '$categoryId.$tokenId';

  /// Returns `(categoryId, tokenId)` for a dotted id, or `null` if the
  /// input is not a valid `category.token` pair.
  static (String, String)? splitDottedId(String dotted) {
    final dot = dotted.indexOf('.');
    if (dot <= 0 || dot == dotted.length - 1) return null;
    return (dotted.substring(0, dot), dotted.substring(dot + 1));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CruxColorTheme) return false;
    if (other.id != id) return false;
    if (other.displayName != displayName) return false;
    if (other.brightness != brightness) return false;
    if (other.tokens.length != tokens.length) return false;
    for (final entry in tokens.entries) {
      final otherCategory = other.tokens[entry.key];
      if (otherCategory == null) return false;
      if (!mapEquals(otherCategory, entry.value)) return false;
    }
    return true;
  }

  /// Cached because this is an `@immutable` value type that flows
  /// through `ThemeData.extensions`, where Flutter hashes it on every
  /// theme comparison — and computing it sorts every key list and
  /// allocates two lists per category. The value can never change.
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
      Object.hashAll(categoryHashes),
    );
  }

  @override
  String toString() {
    var count = 0;
    for (final inner in tokens.values) {
      count += inner.length;
    }
    return 'CruxColorTheme($id, ${brightness.name}, $count tokens)';
  }

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
