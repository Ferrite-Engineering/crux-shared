// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:crux_telemetry/src/telemetry_service.dart';

/// The inert [TelemetryService]: discards every event.
///
/// Allocation-free in the hot path so unconditional `record(...)` call sites in
/// feature code carry no cost. This is the implementation
/// `telemetryServiceProvider` resolves for the whole of the public beta, and
/// afterwards for anyone who declines — `LiveTelemetryService` is the other
/// branch of the same switch, in this same directory.
class NoopTelemetryService implements TelemetryService {
  /// Const constructor so the provider can return a singleton without any
  /// allocation.
  const NoopTelemetryService();

  @override
  void record(TelemetryEvent event) {
    // Intentionally empty — this build does not collect telemetry.
  }
}
