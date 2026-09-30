// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:flutter/material.dart';

/// Flutter [ThemeExtension] that wraps the active [CruxColorTheme] so
/// widgets can read named tokens through `Theme.of(context)`.
///
/// Wire it into the app's `ThemeData.extensions` list at build time,
/// usually inside a `Consumer` that watches `cruxColorThemeProvider`:
///
/// ```dart
/// final theme = ref.watch(cruxColorThemeProvider);
/// return MaterialApp(
///   theme: ThemeData(
///     brightness: theme.brightness,
///     extensions: [CruxThemeExtension(theme: theme)],
///   ),
///   home: ...,
/// );
/// ```
///
/// Read from the widget tree:
///
/// ```dart
/// final cx = Theme.of(context).extension<CruxThemeExtension>()!;
/// final bg = cx.color('canvas', 'background');
/// ```
///
/// [lerp] interpolates per-token via [Color.lerp] so MaterialApp's
/// built-in theme transition animates smoothly across preset
/// switches. Tokens present in one theme but absent in the other are
/// carried through unchanged.
@immutable
class CruxThemeExtension extends ThemeExtension<CruxThemeExtension> {
  /// Creates an extension wrapping [theme]. The wrapped theme is the
  /// single source of truth for every token lookup.
  const CruxThemeExtension({required this.theme});

  /// The active color theme this extension exposes.
  final CruxColorTheme theme;

  /// Returns the color for `(categoryId, tokenId)`, or `null` if the
  /// theme has no entry. Mirrors [CruxColorTheme.color].
  Color? color(String categoryId, String tokenId) =>
      theme.color(categoryId, tokenId);

  /// Returns the color for `(categoryId, tokenId)`, falling back to
  /// [fallback] if absent. Mirrors [CruxColorTheme.colorOr].
  Color colorOr(String categoryId, String tokenId, Color fallback) =>
      theme.colorOr(categoryId, tokenId, fallback);

  /// True if `(categoryId, tokenId)` has an explicit color in this
  /// theme. Mirrors [CruxColorTheme.hasToken].
  bool hasToken(String categoryId, String tokenId) =>
      theme.hasToken(categoryId, tokenId);

  @override
  CruxThemeExtension copyWith({CruxColorTheme? theme}) =>
      CruxThemeExtension(theme: theme ?? this.theme);

  @override
  CruxThemeExtension lerp(
    covariant ThemeExtension<CruxThemeExtension>? other,
    double t,
  ) {
    if (other is! CruxThemeExtension) return this;
    if (identical(theme, other.theme)) return this;
    // Identity fast-path: when either end is already where we are, no
    // need to allocate.
    if (t == 0) return this;
    if (t == 1) return other;

    // The key unions are invariant for a given (from, to) pair, but
    // ThemeData.lerp calls this once per frame for the whole
    // transition — so recomputing a category-key Set plus a token-key
    // Set per category, every frame, was pure garbage. Compute the
    // shape once and reuse it for every subsequent t.
    final plan = _LerpPlan.forPair(theme, other.theme);

    final merged = <String, Map<String, Color>>{};
    for (final step in plan.steps) {
      final left = theme.tokens[step.categoryId];
      final right = other.theme.tokens[step.categoryId];
      if (left == null) {
        merged[step.categoryId] = Map<String, Color>.from(right!);
        continue;
      }
      if (right == null) {
        merged[step.categoryId] = Map<String, Color>.from(left);
        continue;
      }
      final tokens = <String, Color>{};
      for (final tokenId in step.tokenIds) {
        final l = left[tokenId];
        final r = right[tokenId];
        if (l == null) {
          tokens[tokenId] = r!;
        } else if (r == null) {
          tokens[tokenId] = l;
        } else {
          // Color.lerp never returns null when both args are non-null.
          tokens[tokenId] = Color.lerp(l, r, t)!;
        }
      }
      merged[step.categoryId] = tokens;
    }

    // Pick the destination metadata once we're past the midpoint so
    // identity/brightness flip with the perceived theme.
    final destination = t < 0.5 ? theme : other.theme;
    return CruxThemeExtension(
      // `merged` was just built here and is not retained anywhere else,
      // so the defensive deep copy CruxColorTheme's public constructor
      // performs would re-walk every category for no benefit — on the
      // one path in the package that genuinely runs per frame.
      theme: CruxColorTheme.internalUnsafe(
        id: destination.id,
        displayName: destination.displayName,
        brightness: destination.brightness,
        tokens: merged,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CruxThemeExtension && other.theme == theme;
  }

  @override
  int get hashCode => theme.hashCode;

  /// Test seam: number of times a [_LerpPlan] has been computed from
  /// scratch. A transition over N frames should bump this once, not N
  /// times.
  @visibleForTesting
  static int get lerpPlanBuildCount => _LerpPlan._buildCount;

  /// Test seam: drops the cached plan so a test can assert on a fresh
  /// pair.
  @visibleForTesting
  static void resetLerpPlanCacheForTesting() {
    _LerpPlan._cached = null;
    _LerpPlan._buildCount = 0;
  }
}

/// The invariant *shape* of a lerp between two themes: which categories
/// to visit, and which token ids each contributes.
///
/// Depends only on the key sets of the two themes, never on `t`, so one
/// plan serves every frame of a transition. A single-entry cache is
/// enough: `ThemeData.lerp` drives one transition at a time, and a
/// miss simply costs what the old code paid unconditionally.
class _LerpPlan {
  _LerpPlan(this.from, this.to, this.steps);

  factory _LerpPlan.forPair(CruxColorTheme from, CruxColorTheme to) {
    final cached = _cached;
    if (cached != null &&
        identical(cached.from, from) &&
        identical(cached.to, to)) {
      return cached;
    }
    _buildCount++;
    final steps = <_LerpStep>[];
    final categoryIds = <String>{...from.tokens.keys, ...to.tokens.keys};
    for (final categoryId in categoryIds) {
      final left = from.tokens[categoryId];
      final right = to.tokens[categoryId];
      steps.add(
        _LerpStep(
          categoryId,
          left == null || right == null
              // Whole-map copy path; the token list is unused.
              ? const <String>[]
              : <String>{...left.keys, ...right.keys}.toList(growable: false),
        ),
      );
    }
    final plan = _LerpPlan(from, to, steps);
    _cached = plan;
    return plan;
  }

  static _LerpPlan? _cached;
  static int _buildCount = 0;

  final CruxColorTheme from;
  final CruxColorTheme to;
  final List<_LerpStep> steps;
}

class _LerpStep {
  const _LerpStep(this.categoryId, this.tokenIds);

  final String categoryId;
  final List<String> tokenIds;
}
