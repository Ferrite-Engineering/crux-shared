// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

/// A product-supplied set of token values layered onto the shared
/// built-in presets.
///
/// `crux_theme` ships six brand-neutral presets (`builtinPresets()`) that
/// carry only suite-wide `chrome` tokens. Domain-specific token
/// categories — WaveCrux's waveform `canvas`, a future NetCrux
/// `schematic`, a SimCrux `plot` — are *not* shared vocabulary and must
/// never be baked into those presets: a product that has no waveform
/// canvas would otherwise ship (and expose in Settings → Appearance) a
/// full waveform palette it can never use.
///
/// The seam is the same one products already use for schema
/// registration. A product registers its `ThemeTokenCategory` with
/// `ThemeRegistry.registerCategory` to declare *what* tokens exist and
/// what their brightness defaults are, and registers a
/// [PresetTokenOverlay] to declare *what values those tokens take in
/// each shared preset*.
///
/// Example — WaveCrux contributing its canvas palette:
///
/// ```dart
/// ThemeRegistry.instance
///   ..registerCategory(canvasTokens)
///   ..registerPresetOverlay(
///     const PresetTokenOverlay(
///       categoryId: 'canvas',
///       byPresetId: {
///         'crux-dark': {'background': Color(0xFF1A1A1A), ...},
///         'oscilloscope': {'background': Color(0xFF000000), ...},
///       },
///     ),
///   );
/// ```
///
/// Degradation is graceful and total: a product that registers no
/// overlay simply gets presets without that category, and any lookup
/// through `ThemeRegistry.resolve` falls back to the registered
/// descriptor's brightness default exactly as it does for a theme pack
/// that omits a token. Nothing throws, and no product carries another
/// product's palette.
@immutable
class PresetTokenOverlay {
  /// Creates an overlay contributing [categoryId] values to the presets
  /// named in [byPresetId].
  const PresetTokenOverlay({
    required this.categoryId,
    required this.byPresetId,
  });

  /// Token category these values belong to. Should match the id of a
  /// `ThemeTokenCategory` the same product registers, so the Settings →
  /// Appearance editor can render display names for the tokens.
  final String categoryId;

  /// Values keyed by built-in preset id, then by token id.
  ///
  /// Preset ids that are not built-in are ignored rather than treated
  /// as an error — this lets a product ship an overlay entry for a
  /// preset that a newer or older `crux_theme` does not have.
  final Map<String, Map<String, Color>> byPresetId;

  /// Returns the token values this overlay contributes to [presetId],
  /// or `null` when it contributes nothing.
  Map<String, Color>? tokensFor(String presetId) => byPresetId[presetId];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PresetTokenOverlay) return false;
    if (other.categoryId != categoryId) return false;
    if (other.byPresetId.length != byPresetId.length) return false;
    for (final entry in byPresetId.entries) {
      final theirs = other.byPresetId[entry.key];
      if (theirs == null) return false;
      if (!mapEquals(theirs, entry.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final presetHashes = <int>[];
    final sortedPresets = byPresetId.keys.toList()..sort();
    for (final presetId in sortedPresets) {
      final inner = byPresetId[presetId]!;
      final innerKeys = inner.keys.toList()..sort();
      presetHashes.add(
        Object.hash(
          presetId,
          Object.hashAll([
            for (final k in innerKeys) Object.hash(k, inner[k]),
          ]),
        ),
      );
    }
    return Object.hash(categoryId, Object.hashAll(presetHashes));
  }

  @override
  String toString() =>
      'PresetTokenOverlay($categoryId, ${byPresetId.length} presets)';
}
