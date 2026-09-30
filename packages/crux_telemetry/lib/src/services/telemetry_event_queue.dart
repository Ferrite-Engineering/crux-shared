// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:path_provider/path_provider.dart';

/// Hard cap on queued events. Beyond this the **oldest** are dropped.
///
/// The cap is what keeps an app that never reaches the network from growing an
/// unbounded file on the user's disk. Dropping the oldest rather than refusing
/// the newest keeps the surviving window the recent one, which is the window
/// any roadmap question is about.
const int kTelemetryMaxQueuedEvents = 2000;

/// Queued events older than this are discarded unsent.
///
/// A counter from a fortnight-old session answers no question that the same
/// counter from this week does not answer better, and holding it costs the
/// user disk space to no one's benefit.
const Duration kTelemetryEventMaxAge = Duration(days: 7);

/// The append-only on-disk event queue backing `LiveTelemetryService`.
///
/// Stored as **JSON Lines** at `{appSupportDir}/telemetry_queue.jsonl`: one
/// event per line, appended with a single write. A single JSON array would
/// have to be re-encoded in full on every `record()`, which is exactly the
/// work the "never block the UI" contract forbids doing on a feature call
/// path. Line-oriented also fails soft — a line truncated by a power cut costs
/// that line, not the file.
///
/// On web, and anywhere `path_provider` is unavailable, every method degrades
/// to a no-op or an empty return and the service runs memory-only: telemetry
/// simply spans one session there rather than surviving a restart.
///
/// [directoryFactory] is the storage seam — tests point it at a temp
/// directory, and a factory that throws is indistinguishable from a platform
/// with no app-support dir.
class TelemetryEventQueue {
  /// Creates a queue. All three limits are injectable so the prune and cap
  /// behaviours are testable without waiting a week or writing 2000 events.
  TelemetryEventQueue({
    this.directoryFactory,
    this.maxEvents = kTelemetryMaxQueuedEvents,
    this.maxAge = kTelemetryEventMaxAge,
  });

  /// The queue file name inside the app support directory.
  static const fileName = 'telemetry_queue.jsonl';

  /// Resolves the directory the queue file lives in, or `null` to use the
  /// platform's application-support directory. The storage seam tests point at
  /// a temp directory.
  final Future<Directory> Function()? directoryFactory;

  /// Hard cap on retained events.
  final int maxEvents;

  /// Age beyond which a queued event is discarded.
  final Duration maxAge;

  /// Whether this queue actually has a file behind it.
  ///
  /// `false` on web, and anywhere else the directory cannot be resolved — the
  /// same condition under which every other method here degrades to a no-op.
  /// The caller that needs to know is `LiveTelemetryService`: with no file
  /// there is no handover to a next launch, so its whole flush cadence changes.
  /// Asked rather than inferred from an empty [load], because an empty load is
  /// also what a perfectly healthy first launch returns.
  Future<bool> hasPersistentBacking() async => await _queueFile() != null;

  /// Reads the persisted queue, pruned and capped as of [now].
  ///
  /// Unparseable lines are skipped rather than failing the load: the file may
  /// have been written by an older build, and one bad line must not cost the
  /// rest of the queue — the same best-effort posture the Worker takes toward
  /// an unrecognised event.
  Future<List<TelemetryEvent>> load({required DateTime now}) async {
    try {
      final file = await _queueFile();
      if (file == null || !file.existsSync()) return <TelemetryEvent>[];
      final events = <TelemetryEvent>[];
      for (final line in const LineSplitter().convert(
        await file.readAsString(),
      )) {
        final event = _decodeEvent(line);
        if (event != null) events.add(event);
      }
      return pruneTelemetryEvents(
        events,
        now: now,
        maxAge: maxAge,
        maxEvents: maxEvents,
      );
    } on Object catch (_) {
      // A queue we cannot read is a queue we do not have.
      return <TelemetryEvent>[];
    }
  }

  /// Appends one event to the queue file.
  Future<void> append(TelemetryEvent event) async {
    try {
      final file = await _queueFile();
      if (file == null) return;
      await file.writeAsString(
        '${jsonEncode(_encodeEvent(event))}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (_) {
      // Losing a counter is not worth surfacing anything to anyone.
    }
  }

  /// Rewrites the queue file to hold exactly [events].
  ///
  /// Called after a flush drops what was accepted, and after a prune. Deletes
  /// the file outright when nothing remains, so an idle installation leaves no
  /// telemetry artifact behind on disk.
  Future<void> replaceAll(List<TelemetryEvent> events) async {
    try {
      final file = await _queueFile();
      if (file == null) return;
      if (events.isEmpty) {
        if (file.existsSync()) await file.delete();
        return;
      }
      final buffer = StringBuffer();
      for (final event in events) {
        buffer.writeln(jsonEncode(_encodeEvent(event)));
      }
      await file.writeAsString(buffer.toString(), flush: true);
    } on Object catch (_) {
      // Non-fatal — the in-memory queue stays authoritative for this session.
    }
  }

  Future<File?> _queueFile() async {
    try {
      final factory = directoryFactory;
      final dir = factory != null
          ? await factory()
          : await getApplicationSupportDirectory();
      return File('${dir.path}/$fileName');
    } on Object catch (_) {
      return null;
    }
  }
}

/// Drops events older than [maxAge], then the oldest events above [maxEvents].
///
/// Age is evaluated before the cap so a burst of recent events is never
/// discarded to make room for stale ones.
List<TelemetryEvent> pruneTelemetryEvents(
  List<TelemetryEvent> events, {
  required DateTime now,
  Duration maxAge = kTelemetryEventMaxAge,
  int maxEvents = kTelemetryMaxQueuedEvents,
}) {
  final cutoff = now.subtract(maxAge);
  final fresh = events
      .where((event) => !event.timestamp.isBefore(cutoff))
      .toList();
  if (fresh.length <= maxEvents) return fresh;
  return fresh.sublist(fresh.length - maxEvents);
}

Map<String, Object?> _encodeEvent(TelemetryEvent event) => <String, Object?>{
  'name': event.name,
  if (event.properties.isNotEmpty) 'properties': event.properties,
  'timestamp': event.timestamp.toUtc().toIso8601String(),
};

TelemetryEvent? _decodeEvent(String line) {
  if (line.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, Object?>) return null;
    final name = decoded['name'];
    final timestamp = DateTime.tryParse(decoded['timestamp'] as String? ?? '');
    if (name is! String || timestamp == null) return null;
    final properties = decoded['properties'];
    return TelemetryEvent(
      name,
      properties: properties is Map<String, Object?> ? properties : null,
      timestamp: timestamp,
    );
  } on Object catch (_) {
    return null;
  }
}
