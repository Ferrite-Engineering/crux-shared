// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 contrast for every built-in preset's chrome tokens.
///
/// A suite-wide audit graded accessibility **D** and the remediation closed the
/// obvious half: Flutter's guideline matchers now run over six shared surfaces
/// in both brightnesses. That sweep tests **one colour pair** — the seeded
/// default — and the suite ships six presets. A preset is exactly where a
/// contrast regression hides, because nothing renders it in CI and the person
/// who picks "Oscilloscope" is not the person who wrote the widget.
///
/// This checks the presets *directly* rather than by pumping widgets, which is
/// deliberate and is the stronger test: a widget sweep only covers the token
/// pairs a fixture happens to render, while the token table is the complete
/// set of decisions a preset makes. It also means the failure names the token,
/// not the widget that happened to show it.
///
/// ## Which threshold applies to what
///
/// WCAG 2.1 AA asks for **4.5:1** for body text, and **3:1** for large text and
/// for "graphical objects and user interface components" (SC 1.4.11) — the
/// non-text things you must be able to perceive to operate the app. Every pair
/// below is classified explicitly, because getting that classification wrong in
/// either direction is how a contrast suite becomes theatre: too strict and it
/// is disabled, too loose and it passes a status bar nobody can read.
///
/// ## Three presets ship no chrome tokens, and they are checked differently
///
/// `crux-dark`, `crux-light` and `high-contrast-dark` declare an empty token
/// map: their chrome comes from Material 3's derivation of the seed colour.
/// Those are covered by the seed-derivation group below, which measures the
/// `ColorScheme` pairs directly. They are also asserted to *be* empty, so a
/// token added to one later cannot slip past the token group unchecked.
///
/// **`high-contrast-dark` is worth knowing about.** Its chrome is identical to
/// `crux-dark` — 14.33:1 on the primary text pair, comfortably AA, but no more
/// contrasty than the ordinary dark preset. What it actually raises is the
/// *canvas*: WaveCrux maps the preset id to a high-contrast waveform overlay
/// (`wavecrux_canvas_preset_overlay.dart`). That is a defensible design — the
/// canvas is where WaveCrux's contrast problems live — but a user selecting a
/// preset called "High Contrast Dark" for accessibility reasons may reasonably
/// expect the chrome to change too, and today it does not. Flutter's own
/// `ColorScheme.highContrastDark()` would give 18.73:1. Recorded rather than
/// changed, because picking new chrome colours is a design decision.
void main() {
  final presets = builtinPresets();

  test('every built-in preset is covered by this file', () {
    // Non-vacuity. A preset added without a case below would otherwise be
    // untested by a suite whose whole claim is that it covers all of them.
    expect(
      presets.keys.toSet(),
      {
        'crux-dark',
        'crux-light',
        'solarized-dark',
        'high-contrast-dark',
        'oscilloscope',
        'oled-xr',
      },
      reason:
          'A built-in preset was added or renamed. Add it here — and check its '
          'chrome tokens, which is what the rest of this file does.',
    );
  });

  group('seed-derived presets declare no chrome tokens', () {
    for (final id in const ['crux-dark', 'crux-light', 'high-contrast-dark']) {
      test(id, () {
        expect(
          presets[id]!.tokens,
          isEmpty,
          reason:
              '$id gained chrome tokens. It used to derive everything from the '
              'seed colour, which is what let the widget-level guideline '
              'sweeps cover it. Add its pairs to _pairs below.',
        );
      });
    }
  });

  _seedDerivedGroup();

  group('chrome token contrast (WCAG 2.1 AA)', () {
    for (final id in const ['solarized-dark', 'oscilloscope', 'oled-xr']) {
      group(id, () {
        final chrome = presets[id]!.tokens['chrome'] ?? const {};

        test('declares the chrome tokens this suite checks', () {
          // A preset that stops declaring a pair stops being checked for it,
          // silently. This makes that a failure rather than a gap.
          final missing = <String>[];
          for (final pair in _pairs) {
            if (!chrome.containsKey(pair.foreground) ||
                !chrome.containsKey(pair.background)) {
              missing.add('${pair.foreground} on ${pair.background}');
            }
          }
          expect(
            missing,
            isEmpty,
            reason:
                '$id no longer declares:\n${missing.join('\n')}\n\n'
                'If the token was deliberately dropped so the preset inherits '
                'the Material derivation, remove the pair from _pairs and say '
                'why. Leaving it here means it is not checked anywhere.',
          );
        });

        for (final pair in _pairs) {
          test('${pair.foreground} on ${pair.background}', () {
            final declared = chrome[pair.foreground];
            final bg = chrome[pair.background];
            if (declared == null || bg == null) return; // reported above

            // A translucent foreground is seen blended over its background,
            // so that blend is what gets measured.
            final fg = Color.alphaBlend(declared, bg);
            final ratio = _contrastRatio(fg, bg);
            final shortfall = _knownShortfalls[(id, pair.foreground)];
            if (shortfall != null) {
              expect(
                ratio,
                lessThan(pair.minimum),
                reason:
                    '$id: ${pair.foreground} was recorded as falling short '
                    '($shortfall) and now clears ${pair.minimum}:1 '
                    '(${ratio.toStringAsFixed(2)}:1). Remove its '
                    '_knownShortfalls entry so the pair is checked again.',
              );
              return;
            }
            expect(
              ratio,
              greaterThanOrEqualTo(pair.minimum),
              reason:
                  '$id: ${pair.foreground} on ${pair.background} is '
                  '${ratio.toStringAsFixed(2)}:1, below the '
                  '${pair.minimum}:1 this pair needs.\n\n'
                  '${pair.why}\n\n'
                  'Foreground ${_hex(fg)}, background ${_hex(bg)}. Adjust the '
                  'preset — do not lower the threshold, which is fixed by WCAG '
                  '2.1 AA and is what a procurement questionnaire asks about.',
            );
          });
        }
      });
    }
  });
}

/// The seed-derived chrome, which three of the six presets rely on entirely.
///
/// Asserting the token-less presets are empty proves they inherit; it does not
/// prove what they inherit is legible. This measures the pairs Material 3
/// derives from the suite seed colour, in both brightnesses.
void _seedDerivedGroup() {
  const seed = Color(0xFF4650C8);

  for (final brightness in Brightness.values) {
    group('seed-derived chrome (${brightness.name})', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      );

      for (final pair in <({String name, Color fg, Color bg, double min})>[
        (
          name: 'onSurface on surface',
          fg: scheme.onSurface,
          bg: scheme.surface,
          min: 4.5,
        ),
        (
          name: 'onSurfaceVariant on surface',
          fg: scheme.onSurfaceVariant,
          bg: scheme.surface,
          min: 4.5,
        ),
        (
          name: 'onSurfaceVariant on surfaceContainerHighest',
          fg: scheme.onSurfaceVariant,
          bg: scheme.surfaceContainerHighest,
          min: 4.5,
        ),
        (
          name: 'onPrimary on primary',
          fg: scheme.onPrimary,
          bg: scheme.primary,
          min: 4.5,
        ),
        (
          name: 'primary on surface',
          fg: scheme.primary,
          bg: scheme.surface,
          min: 4.5,
        ),
        (
          name: 'onError on error',
          fg: scheme.onError,
          bg: scheme.error,
          min: 4.5,
        ),
        // `outline` is a *border* token. It is checked at the 3:1 UI-component
        // threshold on purpose: it measures 4.26:1 in light, and the audit's
        // command-palette finding was somebody using it as text, where 4.5
        // would have applied and it would have failed.
        (
          name: 'outline on surface (border, not text)',
          fg: scheme.outline,
          bg: scheme.surface,
          min: 3,
        ),
      ]) {
        test(pair.name, () {
          final ratio = _contrastRatio(pair.fg, pair.bg);
          expect(
            ratio,
            greaterThanOrEqualTo(pair.min),
            reason:
                'Seed-derived ${pair.name} is ${ratio.toStringAsFixed(2)}:1 in '
                '${brightness.name}, below ${pair.min}:1. This affects '
                'crux-dark, crux-light and high-contrast-dark, which ship no '
                'chrome tokens of their own — so it is three presets, not one.',
          );
        });
      }
    });
  }
}

/// A foreground/background pair a preset declares, and what it is for.
class _Pair {
  const _Pair({
    required this.foreground,
    required this.background,
    required this.minimum,
    required this.why,
  });

  final String foreground;
  final String background;

  /// 4.5 for body text, 3.0 for large text and UI components (SC 1.4.11).
  final double minimum;

  /// Why this pair carries the threshold it does. Written out because the
  /// classification is the judgement call in this file, not the arithmetic.
  final String why;
}

// Four pairs this file used to check are gone because the presets no longer
// declare their tokens: `tabBar.label` on `tabBar.background`,
// `toolbar.iconActive` on `toolbar.background`, `tabBar.selected` on
// `tabBar.background`, and `splitter.hover` on `panel.background`. Nothing
// painted with those tokens while the presets declared them, so the numbers
// measured colours no user saw. When the tokens reached their widgets each
// preset was pinned to what it already showed, and those surfaces showed the
// host product's own Material colours (`primary`, `outlineVariant`, the body
// text colour, and no strip fill at all), which differ per product and are
// covered by each product's own guideline sweeps, not by a token table.
const _pairs = <_Pair>[
  _Pair(
    foreground: 'panel.header.foreground',
    background: 'panel.header.background',
    minimum: 4.5,
    why:
        'Panel headers are body-sized text naming the panel. A user who '
        'cannot read them cannot tell the docked panels apart.',
  ),
  _Pair(
    foreground: 'statusBar.foreground',
    background: 'statusBar.background',
    minimum: 4.5,
    why:
        'The status bar is the smallest sustained text in the app and it '
        'carries live state — the file, the run, the counts. Small text is '
        'the case AA 4.5:1 exists for.',
  ),
  _Pair(
    foreground: 'toolbar.icon',
    background: 'toolbar.background',
    minimum: 3,
    why:
        'Toolbar icons are user interface components under SC 1.4.11: they '
        'must be perceivable to be operable, but they are not text.',
  ),
];

/// Pairs a preset paints below their threshold, recorded instead of fixed.
///
/// Each preset must render exactly as it has shipped, so a colour cannot be
/// raised here without that being a visible design change. An entry must
/// still fall short: once the colour is raised, the test fails until the
/// entry is removed, so the record cannot outlive the problem.
///
/// Empty. The last entry was Solarized Dark's status bar text, #93A1A1 at
/// 75 % over #002B36 (3.76:1); the preset now paints it opaque (5.61:1).
const _knownShortfalls = <(String, String), String>{};

/// WCAG 2.1 relative luminance.
///
/// The 0.03928 threshold and the 2.4 exponent are from the specification
/// (SC 1.4.3 definitions), not an approximation — a contrast suite that
/// computes its own numbers slightly differently reports passes nobody else
/// agrees with.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

String _hex(Color c) {
  int byte(double v) => (v * 255).round().clamp(0, 255);
  return '#'
          '${byte(c.r).toRadixString(16).padLeft(2, '0')}'
          '${byte(c.g).toRadixString(16).padLeft(2, '0')}'
          '${byte(c.b).toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}
