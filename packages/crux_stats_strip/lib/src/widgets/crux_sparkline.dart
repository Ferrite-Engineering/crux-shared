// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A miniature line chart rendering a sequence of recent values
/// left-to-right.
///
/// Points are evenly spaced horizontally; the Y axis auto-scales to the
/// data range with a small padding at each edge so the line never touches
/// the border. Fewer than two points renders nothing — a single sample is
/// not a trend, and drawing a dot implies more information than exists.
///
/// Ported from WaveCrux's shipped `SparklineWidget` when SimCrux and
/// NetCrux became the second and third consumers.
class CruxSparkline extends StatelessWidget {
  /// Creates a sparkline.
  const CruxSparkline({
    required this.values,
    super.key,
    this.width = 80,
    this.height = 24,
    this.lineColor,
    this.strokeWidth = 1.5,
    this.semanticLabel,
  });

  /// Data points in chronological order (most recent last).
  final List<double> values;

  /// Widget width in logical pixels.
  final double width;

  /// Widget height in logical pixels.
  final double height;

  /// Stroke color — defaults to the current `colorScheme.primary`.
  final Color? lineColor;

  /// Thickness of the polyline in logical pixels.
  final double strokeWidth;

  /// Accessibility label passed to [Semantics].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = lineColor ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _CruxSparklinePainter(
            values: values,
            color: color,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _CruxSparklinePainter extends CustomPainter {
  _CruxSparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    // Padding so the line never touches the very top or bottom edge.
    const paddingFraction = 0.1;
    final pad = range == 0
        ? size.height * paddingFraction
        : range * paddingFraction;
    final lo = minVal - pad;
    final hi = maxVal + pad;
    final span = hi - lo;

    double valueToY(double v) {
      if (span == 0) return size.height / 2;
      // Invert: higher values go toward the top (y = 0).
      return size.height * (1.0 - (v - lo) / span);
    }

    final n = values.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final y = valueToY(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CruxSparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
