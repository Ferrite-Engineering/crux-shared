// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:crux_telemetry/src/services/telemetry_event_queue.dart';
import 'package:crux_telemetry/src/telemetry_service.dart';
import 'package:meta/meta.dart';

/// The [TelemetryService] handed out while the consent decision is **not yet
/// known** — holds events in memory and transmits nothing.
///
/// There is a real third state between "collect" and "do not collect".
/// `TelemetryConsentStore` publishes `unset` synchronously and reads the
/// persisted value back asynchronously, so for the first frames of a cold start
/// a stored refusal and a genuine first launch are the same value. The gate
/// must not transmit in that window, or a stored refusal leaks — but resolving
/// `NoopTelemetryService` there does something else, and it is not benign: it
/// **discards** every event recorded before the store settles.
///
/// Which is every launch event there is. The store's load does not even start
/// until something reads the telemetry graph, and on all four products the
/// first read *is* the launch counter — `workspace.restored`, emitted from a
/// notifier's `build`. On desktop and mobile that costs the one event; on web,
/// where a passive session may record nothing else at all, it costs the
/// session, which is exactly the zero-rows outcome volatile mode exists to
/// prevent.
///
/// So the window buffers instead. Nothing here touches the network, the disk,
/// or the consent decision; the events sit in memory until the store settles
/// and the gate resolves, and then they are either replayed into
/// `LiveTelemetryService` or dropped with the buffer. Buffering is not
/// collecting: an installation that turns out to have refused transmits
/// nothing, and the buffer it never sent is discarded whole.
///
/// **This never runs during the beta.** The dark-launch branch of the gate
/// returns "closed" synchronously and definitively — there is nothing to
/// settle, so there is no pending state to be in.
class PendingTelemetryService implements TelemetryService {
  /// Buffers into [buffer], dropping the oldest beyond [maxEvents].
  ///
  /// The list is owned by the provider container rather than by this object,
  /// because the whole point is that it outlives this object: the service is
  /// replaced the moment the gate resolves, and the events have to survive that
  /// replacement to be worth buffering at all.
  PendingTelemetryService(
    this.buffer, {
    this.maxEvents = kTelemetryMaxQueuedEvents,
  });

  /// The container-scoped buffer this service appends to.
  final List<TelemetryEvent> buffer;

  /// Cap on the buffer, mirroring the queue's own. A consent store that never
  /// answers must not grow a list without bound.
  final int maxEvents;

  @override
  void record(TelemetryEvent event) {
    // Same contract as every other implementation: synchronous, `void`, total.
    try {
      buffer.add(event);
      if (buffer.length > maxEvents) {
        buffer.removeRange(0, buffer.length - maxEvents);
      }
    } on Object catch (_) {
      // Swallowed by design — telemetry never throws into a feature flow.
    }
  }

  /// Events held so far. Exposed for tests.
  @visibleForTesting
  List<TelemetryEvent> get pending => List<TelemetryEvent>.unmodifiable(buffer);
}
