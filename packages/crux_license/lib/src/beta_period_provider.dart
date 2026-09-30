// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/beta_period.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod-overridable view of [kBetaPeriod] for tests and runtime
/// experiments.
///
/// The build-time constant [kBetaPeriod] remains the production source of
/// truth — feature code that wants the simplest gate check still calls
/// `FeatureGate.isAvailable(required, current)`, which reads the constant
/// directly. This provider exists so tests (and any future remote
/// configuration that wants to flip beta status without a rebuild) can
/// override the value via `betaPeriodProvider.overrideWithValue(false)` to
/// exercise the post-beta gating path.
///
/// Feature code that wants to honor the override consults this provider in
/// addition to the tier:
///
/// ```dart
/// final betaPeriod = ref.watch(betaPeriodProvider);
/// final tier = ref.watch(licenseTierProvider);
/// final unlocked = betaPeriod ||
///     tier.featureEquivalent.index >= LicenseTier.pro.index;
/// ```
///
/// The broader beta policy: badges are visible during beta, gates are open.
final betaPeriodProvider = Provider<bool>(
  (_) => kBetaPeriod,
  name: 'betaPeriodProvider',
);
