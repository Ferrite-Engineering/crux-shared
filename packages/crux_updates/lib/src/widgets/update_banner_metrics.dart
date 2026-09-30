// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Sizing the update banner needs, supplied by the host so the package stays
/// free of any product's device-metrics system.
///
/// WaveCrux builds this from its `MobileMetrics`; other products fill it from
/// their own equivalents. The defaults are the desktop-safe Material values and
/// already satisfy the suite's 44 dp minimum touch target, so
/// `const CruxUpdateBannerMetrics()` is a valid choice for a desktop-only host.
@immutable
class CruxUpdateBannerMetrics {
  /// Creates a metrics bundle. Every field defaults to the desktop value.
  const CruxUpdateBannerMetrics({
    this.touchTarget = 44,
    this.iconSize = 20,
    this.bodyFontSize = 13,
  });

  /// Minimum hit-area edge (dp) for the banner's buttons. Never set this below
  /// 44 — that is the suite-wide accessibility floor.
  final double touchTarget;

  /// Icon size (dp) for the leading update glyph and the dismiss button.
  final double iconSize;

  /// Font size for the banner message.
  final double bodyFontSize;

  /// Returns a copy with the given fields replaced.
  CruxUpdateBannerMetrics copyWith({
    double? touchTarget,
    double? iconSize,
    double? bodyFontSize,
  }) {
    return CruxUpdateBannerMetrics(
      touchTarget: touchTarget ?? this.touchTarget,
      iconSize: iconSize ?? this.iconSize,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxUpdateBannerMetrics &&
          runtimeType == other.runtimeType &&
          touchTarget == other.touchTarget &&
          iconSize == other.iconSize &&
          bodyFontSize == other.bodyFontSize;

  @override
  int get hashCode => Object.hash(touchTarget, iconSize, bodyFontSize);

  @override
  String toString() =>
      'CruxUpdateBannerMetrics(touchTarget: $touchTarget, '
      'iconSize: $iconSize, bodyFontSize: $bodyFontSize)';
}
