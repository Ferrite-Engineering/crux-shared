// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

/// Description of a single themable color token.
///
/// A descriptor is the schema-side metadata each product supplies when
/// registering a [ThemeTokenCategory]. The descriptor's
/// [lightDefault] / [darkDefault] are the colors used when an active
/// theme omits the token, and [displayName] / [description] feed the
/// Settings → Appearance editor.
@immutable
class ThemeTokenDescriptor {
  /// Creates a descriptor for one themable color token.
  const ThemeTokenDescriptor({
    required this.id,
    required this.displayName,
    required this.lightDefault,
    required this.darkDefault,
    this.description,
  });

  /// Stable token id. Combined with its category id to form the full
  /// `category.token` identifier the JSON pack format uses. Must be
  /// non-empty.
  final String id;

  /// Human-readable label shown in the Settings → Appearance editor.
  final String displayName;

  /// Default color used when the active theme has light brightness and
  /// no value for this token.
  final Color lightDefault;

  /// Default color used when the active theme has dark brightness and
  /// no value for this token.
  final Color darkDefault;

  /// Optional explanatory text. Surfaces as a tooltip / helper line in
  /// the Settings UI; not used by the engine itself.
  final String? description;

  /// Returns the default appropriate for [brightness].
  Color defaultFor(Brightness brightness) =>
      brightness == Brightness.light ? lightDefault : darkDefault;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeTokenDescriptor &&
        other.id == id &&
        other.displayName == displayName &&
        other.lightDefault == lightDefault &&
        other.darkDefault == darkDefault &&
        other.description == description;
  }

  @override
  int get hashCode =>
      Object.hash(id, displayName, lightDefault, darkDefault, description);

  @override
  String toString() => 'ThemeTokenDescriptor($id, $displayName)';
}

/// Registered group of themable tokens owned by one product or feature.
///
/// Products call `ThemeRegistry.registerCategory` at startup with a
/// `ThemeTokenCategory` describing each group of tokens they expose
/// (e.g. `canvas`, `chrome` for WaveCrux; product-specific categories
/// for future consumers). The category id namespaces token ids so two
/// products registering a token named `background` never collide.
@immutable
class ThemeTokenCategory {
  /// Creates a token category.
  ///
  /// [id] must be non-empty and unique within the registry. Token ids
  /// must be unique within the category.
  const ThemeTokenCategory({
    required this.id,
    required this.displayName,
    required this.tokens,
  });

  /// Stable category id. Combined with each token id to form the
  /// `category.token` identifier the JSON pack format uses.
  final String id;

  /// Human-readable label shown in the Settings → Appearance editor.
  final String displayName;

  /// Ordered list of token descriptors owned by this category.
  ///
  /// Order is preserved in the UI so products can group related tokens
  /// (e.g. all cursor colors next to each other) by ordering the list
  /// appropriately. The list must contain at least one descriptor.
  final List<ThemeTokenDescriptor> tokens;

  /// Returns the descriptor for [tokenId], or `null` if absent.
  ThemeTokenDescriptor? descriptor(String tokenId) {
    for (final token in tokens) {
      if (token.id == tokenId) return token;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeTokenCategory &&
        other.id == id &&
        other.displayName == displayName &&
        listEquals(other.tokens, tokens);
  }

  @override
  int get hashCode => Object.hash(id, displayName, Object.hashAll(tokens));

  @override
  String toString() => 'ThemeTokenCategory($id, ${tokens.length} tokens)';
}
