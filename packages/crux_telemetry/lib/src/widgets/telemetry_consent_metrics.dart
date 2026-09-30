// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Hit-target floor for every control on the consent surfaces, in logical
/// pixels.
///
/// A deliberate **floor**, not a default: several products drop their touch
/// target to 28 dp on a desktop host. This is the one screen in the app where
/// the user is deciding what leaves their machine, and the rule the suite sets
/// for it is that "off" may never be harder to reach than "on" — so the switch
/// and the Continue button get the touch-sized target on every host, not just
/// on the ones with fingers. [CruxTelemetryConsentMetrics.touchTarget] is
/// raised to this value rather than replaced by it, so a product with a
/// *larger* target keeps it.
const double kTelemetryConsentMinTarget = 44;

/// Sizing the consent disclosure needs, supplied by the host so the package
/// stays free of any product's device-metrics system.
///
/// WaveCrux builds this from its `MobileMetrics`; other products fill it from
/// their own equivalents. The defaults are the desktop-safe Material values and
/// already satisfy [kTelemetryConsentMinTarget], so
/// `const CruxTelemetryConsentMetrics()` is a valid choice for a desktop-only
/// host.
@immutable
class CruxTelemetryConsentMetrics {
  /// Creates a metrics bundle. Every field defaults to the desktop value.
  const CruxTelemetryConsentMetrics({
    this.touchTarget = kTelemetryConsentMinTarget,
    this.iconSize = 18,
    this.bodyFontSize = 13,
  });

  /// Minimum hit-area edge (dp) for the disclosure's controls. Raised to
  /// [kTelemetryConsentMinTarget] by the widget when a host passes less.
  final double touchTarget;

  /// Icon size (dp) for the list bullets and the "learn more" glyph.
  final double iconSize;

  /// Font size for body copy, list items, and the toggle label.
  final double bodyFontSize;

  /// The effective hit target — never below [kTelemetryConsentMinTarget].
  double get effectiveTouchTarget => touchTarget < kTelemetryConsentMinTarget
      ? kTelemetryConsentMinTarget
      : touchTarget;

  /// Returns a copy with the given fields replaced.
  CruxTelemetryConsentMetrics copyWith({
    double? touchTarget,
    double? iconSize,
    double? bodyFontSize,
  }) {
    return CruxTelemetryConsentMetrics(
      touchTarget: touchTarget ?? this.touchTarget,
      iconSize: iconSize ?? this.iconSize,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxTelemetryConsentMetrics &&
          runtimeType == other.runtimeType &&
          touchTarget == other.touchTarget &&
          iconSize == other.iconSize &&
          bodyFontSize == other.bodyFontSize;

  @override
  int get hashCode => Object.hash(touchTarget, iconSize, bodyFontSize);

  @override
  String toString() =>
      'CruxTelemetryConsentMetrics(touchTarget: $touchTarget, '
      'iconSize: $iconSize, bodyFontSize: $bodyFontSize)';
}
