// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single anonymous usage-statistics event.
///
/// Carries an event [name] (a stable string identifier such as
/// `decoder.opened`), an optional [properties] map of scalar values, and the
/// wall-clock [timestamp] at which the event was recorded.
///
/// Telemetry events never carry file names, signal names, hierarchical paths,
/// waveform values, netlist identifiers, or any other potentially sensitive
/// content — only feature-usage signals and small numeric / categorical
/// context. Each product pins its own catalog of permitted event names and the
/// closed vocabulary of each property; this package deliberately holds no
/// catalog, because the catalog is the one part of telemetry that is genuinely
/// per-product.
///
/// Instrumentation call sites construct events unconditionally — the
/// allocation-free `NoopTelemetryService` is what an opted-out or beta build
/// resolves, so no call site ever has to ask whether collection is on.
@immutable
class TelemetryEvent {
  /// Records an event named [name].
  ///
  /// [properties] is copied into an unmodifiable map so a caller that reuses
  /// its builder map cannot mutate an event already handed to the queue.
  /// [timestamp] defaults to now; it is injectable so queue pruning and
  /// coalescing are testable without waiting.
  TelemetryEvent(
    this.name, {
    Map<String, Object?>? properties,
    DateTime? timestamp,
  }) : properties = Map<String, Object?>.unmodifiable(
         properties ?? const <String, Object?>{},
       ),
       timestamp = timestamp ?? DateTime.now();

  /// Stable event identifier (e.g. `decoder.opened`).
  ///
  /// Identifiers are dot-separated namespaces. Reserve the leading namespace
  /// for the broad feature area so dashboards can group cleanly.
  final String name;

  /// Small map of scalar context values (numbers, strings, booleans). Never
  /// signal names, file paths, or other sensitive content.
  final Map<String, Object?> properties;

  /// Wall-clock timestamp at construction time.
  ///
  /// Used for queue ageing only. It is **not** transmitted: per-event client
  /// timestamps would amount to an interaction sequence, and Analytics Engine
  /// stamps its own row time anyway.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryEvent &&
          name == other.name &&
          _mapEquals(properties, other.properties) &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(name, timestamp, properties.length);

  @override
  String toString() =>
      'TelemetryEvent(name: $name, properties: $properties, '
      'timestamp: $timestamp)';
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    if (a[key] != b[key]) return false;
  }
  return true;
}
