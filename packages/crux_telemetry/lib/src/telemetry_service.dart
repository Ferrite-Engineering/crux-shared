// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/models/telemetry_event.dart';

/// Extension point for anonymous usage-statistics collection.
///
/// **Both** implementations ship here: `NoopTelemetryService`, which discards
/// everything, and `LiveTelemetryService`, which queues, batches, and POSTs to
/// the suite ingestion Worker. `telemetryServiceProvider` picks between them
/// from the beta flag, the dev flag, and the stored consent. No Pro overlay
/// holds a telemetry implementation — the honesty backstop for collecting from
/// free users is that the whole pipeline is readable, and strippable, in the
/// Apache-2.0 source, which it cannot be if half of it lives in a closed
/// overlay.
///
/// Call sites should [record] events unconditionally — the no-op implementation
/// is allocation-free and call sites stay tier- and consent-agnostic.
abstract class TelemetryService {
  /// Record an event. The implementation may queue, batch, transmit, or
  /// discard the event; callers must not assume the event has been persisted
  /// by the time this method returns.
  ///
  /// Implementations must never throw — telemetry failures must not break
  /// feature flows.
  void record(TelemetryEvent event);
}
