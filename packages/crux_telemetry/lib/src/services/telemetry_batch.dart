// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_telemetry/src/models/telemetry_envelope.dart';
import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:meta/meta.dart';

/// Maximum events in one POST — `MAX_EVENTS` in the ingestion Worker. Over
/// this the Worker rejects the **whole** batch, so the client splits instead.
const int kTelemetryMaxBatchEvents = 500;

/// Maximum encoded body size in one POST — `MAX_BODY_BYTES` in the Worker.
///
/// The Worker measures `text.length` on the decoded body (UTF-16 units) while
/// this measures UTF-8 bytes. The two agree because every byte a batch can
/// contain is ASCII: event names and property values are constrained to
/// `[a-z0-9_.]`, and every envelope field is a slug, a UUID, a version, or a
/// timestamp.
const int kTelemetryMaxBatchBytes = 64 * 1024;

/// One coalesced row of a batch: an event name, its (already key-sorted)
/// properties, and how many times it occurred.
///
/// Coalescing is what the Worker's `count` field is for. A user who opens
/// forty SPI decoder tabs generates forty queue entries and exactly one batch
/// row — which is both the smaller payload and the more honest one, because
/// `count` is the number Analytics Engine sums.
@immutable
class TelemetryBatchEntry {
  /// Creates a coalesced entry. [properties] must already be key-sorted;
  /// [coalesceTelemetryEvents] is the only intended constructor caller.
  const TelemetryBatchEntry({
    required this.name,
    required this.properties,
    required this.count,
  });

  /// Catalog event name (`decoder.opened`).
  final String name;

  /// Closed-vocabulary properties, sorted by key.
  final Map<String, Object?> properties;

  /// Occurrences this row represents.
  final int count;

  /// The grouping identity — name plus canonicalised properties. Two events
  /// share a row if and only if they share this.
  String get groupKey => telemetryGroupKey(name, properties);

  /// The row as the Worker expects it.
  ///
  /// `properties` is omitted rather than emitted empty, matching
  /// `contract/valid-batch.json`: an event with no properties has no
  /// properties, and an empty object would only be bytes the Worker discards.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (properties.isNotEmpty) 'properties': properties,
    'count': count,
  };
}

/// One ready-to-POST batch: the encoded body plus the entries it carries.
///
/// The entries come back with the body so the caller can drop exactly what a
/// successful POST accepted, rather than clearing a queue that may have grown
/// while the request was in flight.
@immutable
class TelemetryBatch {
  /// Pairs [entries] with the [body] that encodes them.
  const TelemetryBatch({required this.entries, required this.body});

  /// The coalesced rows the [body] encodes.
  final List<TelemetryBatchEntry> entries;

  /// The encoded JSON request body.
  final String body;
}

/// Canonical grouping identity for an event name plus properties.
String telemetryGroupKey(String name, Map<String, Object?> properties) =>
    '$name\x00${jsonEncode(canonicalTelemetryProperties(properties))}';

/// Sorts [properties] by key and drops null values.
///
/// Sorted so the encoding is deterministic — the same two events must always
/// coalesce, whatever order the call sites happened to build their maps in.
/// Nulls are dropped because the Worker cannot encode them and would silently
/// skip the pair anyway; dropping here keeps the client's idea of the payload
/// and the server's identical.
Map<String, Object?> canonicalTelemetryProperties(
  Map<String, Object?> properties,
) {
  final keys = properties.keys.where((k) => properties[k] != null).toList()
    ..sort();
  return <String, Object?>{for (final key in keys) key: properties[key]};
}

/// Folds a chronological event queue into coalesced batch rows.
///
/// Rows come back in **first-occurrence order**, so a batch reads in the order
/// the user did things even though the individual timestamps are gone. The
/// timestamps are not sent at all: Analytics Engine stamps its own row time,
/// and per-event client timestamps would be an interaction sequence, which
/// the pipeline does not collect.
List<TelemetryBatchEntry> coalesceTelemetryEvents(
  Iterable<TelemetryEvent> events,
) {
  final order = <String>[];
  final counts = <String, int>{};
  final canonical =
      <String, ({String name, Map<String, Object?> properties})>{};

  for (final event in events) {
    final properties = canonicalTelemetryProperties(event.properties);
    final key = telemetryGroupKey(event.name, properties);
    if (!counts.containsKey(key)) {
      order.add(key);
      counts[key] = 0;
      canonical[key] = (name: event.name, properties: properties);
    }
    counts[key] = counts[key]! + 1;
  }

  return <TelemetryBatchEntry>[
    for (final key in order)
      TelemetryBatchEntry(
        name: canonical[key]!.name,
        properties: canonical[key]!.properties,
        count: counts[key]!,
      ),
  ];
}

/// Encodes one batch body from [envelope] and [entries].
String encodeTelemetryBatch(
  TelemetryEnvelope envelope,
  List<TelemetryBatchEntry> entries,
) => jsonEncode(<String, Object?>{
  ...envelope.toJson(),
  'events': <Object?>[for (final entry in entries) entry.toJson()],
});

/// Splits [entries] into as many POSTs as the Worker's caps require.
///
/// Sizes are computed additively (envelope overhead + each row + the commas
/// between them) rather than by re-encoding a growing candidate list, which
/// would be quadratic over a full 2000-event queue. The arithmetic is exact
/// for `jsonEncode`'s compact output, which is what is actually sent.
///
/// A single row that cannot fit on its own is **dropped**. It can only arise
/// from a pathological property map, it would 400 forever, and a row that can
/// never be sent must not be allowed to wedge the queue behind it.
List<TelemetryBatch> buildTelemetryBatches(
  TelemetryEnvelope envelope,
  List<TelemetryBatchEntry> entries,
) {
  if (entries.isEmpty) return const <TelemetryBatch>[];

  final overhead = utf8.encode(encodeTelemetryBatch(envelope, const [])).length;

  final batches = <TelemetryBatch>[];
  var current = <TelemetryBatchEntry>[];
  var currentBytes = overhead;

  void seal() {
    if (current.isEmpty) return;
    batches.add(
      TelemetryBatch(
        entries: List<TelemetryBatchEntry>.unmodifiable(current),
        body: encodeTelemetryBatch(envelope, current),
      ),
    );
    current = <TelemetryBatchEntry>[];
    currentBytes = overhead;
  }

  for (final entry in entries) {
    final rowBytes = utf8.encode(jsonEncode(entry.toJson())).length;
    // The comma this row needs when it is not the first in its batch.
    final separator = current.isEmpty ? 0 : 1;

    if (overhead + rowBytes > kTelemetryMaxBatchBytes) continue;

    if (current.length >= kTelemetryMaxBatchEvents ||
        currentBytes + separator + rowBytes > kTelemetryMaxBatchBytes) {
      seal();
      currentBytes = overhead + rowBytes;
      current.add(entry);
      continue;
    }

    currentBytes += separator + rowBytes;
    current.add(entry);
  }
  seal();

  return batches;
}
