// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The color set behind a [CruxGlowingAppIcon]'s halo and shimmer layers.
///
/// Each Crux app supplies its own palette so the welcome-screen glow follows
/// the product's brand color — amber for NetCrux, lint-blue for LintCrux,
/// indigo for SimCrux — while WaveCrux keeps its multicolor waveform palette
/// via the verbatim constructor.
@immutable
class CruxGlowPalette {
  /// Creates a palette from explicit layer colors.
  const CruxGlowPalette({
    required this.background,
    required this.outer,
    required this.middle,
    required this.inner,
    required this.innerCore,
  });

  /// Derives a full palette from one brand [seed] color.
  ///
  /// The layers are hue-shifted and lightness-shifted around the seed so the
  /// glow shimmers with depth instead of reading as one flat tint:
  /// the outer ring carries the seed itself, the middle ring rotates the hue
  /// slightly for a two-tone breath, and the inner backlight lightens toward
  /// a near-white core — the same structure WaveCrux's hand-tuned palette
  /// uses.
  factory CruxGlowPalette.fromSeed(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    HSLColor shift({double hue = 0, double? saturation, double? lightness}) =>
        HSLColor.fromAHSL(
          1,
          (hsl.hue + hue) % 360,
          (saturation ?? hsl.saturation).clamp(0.0, 1.0),
          (lightness ?? hsl.lightness).clamp(0.0, 1.0),
        );
    return CruxGlowPalette(
      background: shift(hue: -20).toColor(),
      outer: seed,
      middle: shift(hue: 35, saturation: 0.9).toColor(),
      inner: shift(lightness: hsl.lightness + 0.12).toColor(),
      innerCore: shift(saturation: 0.55, lightness: 0.88).toColor(),
    );
  }

  /// Broad ambient wash behind everything (slow ~6s breath).
  final Color background;

  /// Outer halo ring (~3.5s breath).
  final Color outer;

  /// Middle halo ring, phase-offset from the outer ring.
  final Color middle;

  /// Tight backlight directly behind the icon.
  final Color inner;

  /// Bright center of the backlight.
  final Color innerCore;
}

/// An app icon surrounded by an animated colored halo and an ambient pulsing
/// background glow — the suite's welcome-screen / About-dialog logo
/// treatment.
///
/// Painted back-to-front:
///   1. Background pulse — broad, low-opacity wash, slow ~6s breath.
///   2. Outer ring — [CruxGlowPalette.outer] halo, ~3.5s breath.
///   3. Middle ring — [CruxGlowPalette.middle] halo, phase-offset.
///   4. Inner backlight — tight [CruxGlowPalette.inner] glow behind the icon.
///   5. The [icon] with a rounded squircle clip and a soft radial edge fade
///      so its boundary blends into the surrounding glow rather than reading
///      as a hard square badge.
///
/// The two animation controllers run independently and on different periods
/// so the layers never pulse in lockstep.
class CruxGlowingAppIcon extends StatefulWidget {
  /// Creates a glowing app icon around [icon], colored by [palette].
  ///
  /// [icon] should render at [size] logical pixels square (typically the
  /// product's resilient app-icon image widget); the glow box reserves
  /// additional space around it.
  const CruxGlowingAppIcon({
    required this.icon,
    required this.palette,
    this.size = 120,
    super.key,
  });

  /// Test hook: when `true`, the halo renders its first frame but the
  /// perpetual `AnimationController.repeat` loops are not started, so
  /// `pumpAndSettle` in host-app widget tests settles normally. Set it once
  /// from `flutter_test_config.dart`; production code never touches it.
  @visibleForTesting
  static bool debugDisableAnimations = false;

  /// The product's app-icon widget, pre-sized to [size].
  final Widget icon;

  /// Brand colors for the halo layers.
  final CruxGlowPalette palette;

  /// Pixel size of the icon itself. The widget reserves additional space
  /// around the icon for the halo and background glow.
  final double size;

  @override
  State<CruxGlowingAppIcon> createState() => _CruxGlowingAppIconState();
}

class _CruxGlowingAppIconState extends State<CruxGlowingAppIcon>
    with TickerProviderStateMixin {
  static const double _darkGlowFactor = 1.7;
  static const double _lightGlowFactor = 1.4;

  late final AnimationController _haloController;
  late final AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
    if (!CruxGlowingAppIcon.debugDisableAnimations) {
      _haloController.repeat(reverse: true);
      _backgroundController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _haloController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glowFactor = isDark ? _darkGlowFactor : _lightGlowFactor;
    final boxSize = widget.size * glowFactor;

    return RepaintBoundary(
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _haloController,
                  _backgroundController,
                ]),
                builder: (context, _) => CustomPaint(
                  painter: _GlowPainter(
                    haloProgress: _haloController.value,
                    backgroundProgress: _backgroundController.value,
                    isDark: isDark,
                    palette: widget.palette,
                  ),
                ),
              ),
            ),
            _SoftenedIcon(size: widget.size, icon: widget.icon),
          ],
        ),
      ),
    );
  }
}

/// The icon clipped to a rounded squircle and faded at the very edges so it
/// blends into the surrounding glow.
class _SoftenedIcon extends StatelessWidget {
  const _SoftenedIcon({required this.size, required this.icon});

  final double size;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: ShaderMask(
        // Keeps the central ~88% of the icon at full opacity, then fades the
        // outer rim to ~25% opacity. The ClipRRect already removes the hard
        // corners; the mask softens the cardinal-direction edges so the
        // transition into the glow is gradual rather than abrupt.
        shaderCallback: (rect) => const RadialGradient(
          radius: 0.85,
          colors: [
            Colors.white,
            Colors.white,
            Color(0x40FFFFFF),
          ],
          stops: [0.0, 0.88, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: icon,
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.haloProgress,
    required this.backgroundProgress,
    required this.isDark,
    required this.palette,
  });

  /// Foreground halo (rings + backlight) progress in [0, 1].
  final double haloProgress;

  /// Background pulse progress in [0, 1]. Driven by a slower controller so
  /// the ambient wash breathes independently of the focused rings.
  final double backgroundProgress;

  final bool isDark;

  final CruxGlowPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;

    // Light theme reuses the same gradient structure at reduced intensity so
    // it reads as a clear aura rather than a neon ring. (Raised from the
    // original 0.35 — the effect was nearly invisible in light mode.)
    final lightFactor = isDark ? 1.0 : 0.55;

    // ── 1. Background pulse — broad, ambient, slow ────────────────────────
    // A simple radial wash from the palette's background tint at the center
    // to transparent at the box edge. Sits behind every other layer and
    // breathes on its own ~6s cycle.
    final bgPhase = Curves.easeInOut.transform(backgroundProgress);
    final bgColor = isDark
        ? palette.background
        : palette.background.withValues(alpha: 0.8);
    final bgOpacity = (0.10 + 0.18 * bgPhase) * lightFactor;
    _drawGlow(
      canvas: canvas,
      center: center,
      // Slightly wider than the box so the gradient never shows a hard edge.
      radius: maxRadius * 1.05,
      colors: [
        bgColor.withValues(alpha: bgOpacity.clamp(0.0, 1.0)),
        bgColor.withValues(alpha: (bgOpacity * 0.55).clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    // ── 2. Outer halo ring ────────────────────────────────────────────────
    final outerPhase = Curves.easeInOut.transform(haloProgress);
    // Phase-offset middle ring so the two foreground rings don't pulse in
    // lockstep.
    final middlePhase = Curves.easeInOut.transform(
      ((haloProgress + 0.4) % 1.0).clamp(0.0, 1.0),
    );

    final outerColor = isDark
        ? palette.outer
        : palette.outer.withValues(alpha: 0.9);
    final outerOpacity = (0.26 + 0.30 * outerPhase) * lightFactor;
    _drawGlow(
      canvas: canvas,
      center: center,
      radius: maxRadius * 0.95,
      colors: [
        Colors.transparent,
        outerColor.withValues(alpha: outerOpacity.clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      stops: const [0.0, 0.7, 1.0],
    );

    // ── 3. Middle halo ring ───────────────────────────────────────────────
    final middleColor = isDark
        ? palette.middle
        : palette.middle.withValues(alpha: 0.85);
    final middleOpacity = (0.18 + 0.24 * middlePhase) * lightFactor;
    _drawGlow(
      canvas: canvas,
      center: center,
      radius: maxRadius * 0.8,
      colors: [
        Colors.transparent,
        middleColor.withValues(alpha: middleOpacity.clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    // ── 4. Inner backlight — tight, mostly static ─────────────────────────
    final innerOpacity = (0.30 + 0.06 * outerPhase) * lightFactor;
    final innerCenterAlpha = (innerOpacity * 0.6).clamp(0.0, 1.0);
    _drawGlow(
      canvas: canvas,
      center: center,
      radius: maxRadius * 0.55,
      colors: [
        palette.innerCore.withValues(alpha: innerCenterAlpha),
        palette.inner.withValues(alpha: innerOpacity.clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
  }

  void _drawGlow({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required List<Color> colors,
    required List<double> stops,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: colors,
        stops: stops,
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) =>
      oldDelegate.haloProgress != haloProgress ||
      oldDelegate.backgroundProgress != backgroundProgress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.palette != palette;
}
