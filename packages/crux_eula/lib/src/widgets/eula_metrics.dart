// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Hit-target floor for the acceptance surface's controls, in logical pixels.
///
/// A **floor**, not a default, for the same reason the telemetry disclosure
/// sets one: several products drop their touch target to 28 dp on desktop, and
/// this is a screen where the user is agreeing to a contract. Accept, Decline
/// and the checkbox get a touch-sized target on every host.
const double kCruxEulaMinTarget = 44;

/// Sizing the acceptance dialog needs, supplied by the host so the package
/// stays free of any product's device-metrics system.
///
/// The defaults are the desktop-safe Material values and already satisfy
/// [kCruxEulaMinTarget], so `const CruxEulaMetrics()` is a valid choice for a
/// desktop-only host.
@immutable
class CruxEulaMetrics {
  /// Creates a metrics bundle. Every field defaults to the desktop value.
  const CruxEulaMetrics({
    this.touchTarget = kCruxEulaMinTarget,
    this.iconSize = 18,
    this.bodyFontSize = 13,
  });

  /// Minimum hit-area edge (dp). Raised to [kCruxEulaMinTarget] by the widget
  /// when a host passes less.
  final double touchTarget;

  /// Icon size (dp) for the "read it online" glyph.
  final double iconSize;

  /// Font size for the agreement body and the checkbox label.
  final double bodyFontSize;

  /// The effective hit target — never below [kCruxEulaMinTarget].
  double get effectiveTouchTarget =>
      touchTarget < kCruxEulaMinTarget ? kCruxEulaMinTarget : touchTarget;

  /// Returns a copy with the given fields replaced.
  CruxEulaMetrics copyWith({
    double? touchTarget,
    double? iconSize,
    double? bodyFontSize,
  }) {
    return CruxEulaMetrics(
      touchTarget: touchTarget ?? this.touchTarget,
      iconSize: iconSize ?? this.iconSize,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxEulaMetrics &&
          runtimeType == other.runtimeType &&
          touchTarget == other.touchTarget &&
          iconSize == other.iconSize &&
          bodyFontSize == other.bodyFontSize;

  @override
  int get hashCode => Object.hash(touchTarget, iconSize, bodyFontSize);

  @override
  String toString() =>
      'CruxEulaMetrics(touchTarget: $touchTarget, iconSize: $iconSize, '
      'bodyFontSize: $bodyFontSize)';
}
