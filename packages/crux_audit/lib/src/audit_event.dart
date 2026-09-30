// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:meta/meta.dart';

/// How much a sink is asked to record.
enum AuditVerbosity {
  /// Record nothing. The sink is inert and writes no file.
  off,

  /// Record the events that answer "who changed what" — the default.
  normal,

  /// Record everything a product registers, including high-frequency events.
  verbose;

  /// Whether an event at [severity] is recorded at this verbosity.
  bool records(AuditSeverity severity) => switch (this) {
    AuditVerbosity.off => false,
    AuditVerbosity.normal => severity != AuditSeverity.debug,
    AuditVerbosity.verbose => true,
  };
}

/// How much an event matters, for filtering rather than for alarm.
enum AuditSeverity {
  /// High-frequency detail, recorded only at [AuditVerbosity.verbose].
  debug,

  /// The ordinary case: something happened that an administrator may want to
  /// see later.
  info,

  /// Something was refused — a plugin outside the allowlist, a policy file
  /// that failed verification.
  warning,

  /// Something failed in a way that needs a human.
  error,
}

/// One audit record, in the envelope every product shares.
///
/// **The envelope is shared; the event KINDS are not.** A kind is a plain
/// string registered by the product — `waiver.created`, `decoder.activated`,
/// `regression.started` — because the set of things worth recording is a
/// product's own business and a shared enum would need editing in
/// `crux-shared` every time any product learned a new one.
///
/// What is fixed here is the shape, so that one JSONL file holding events from
/// four products is still one parseable stream.
@immutable
class AuditEvent {
  /// Creates an event.
  const AuditEvent({
    required this.timestamp,
    required this.product,
    required this.kind,
    this.severity = AuditSeverity.info,
    this.peerId,
    this.payload = const <String, Object?>{},
  });

  /// When it happened, in UTC.
  final DateTime timestamp;

  /// Which product recorded it — `wavecrux`, `netcrux`, `lintcrux`, `simcrux`.
  final String product;

  /// The product-registered event kind.
  final String kind;

  /// How much it matters. Drives [AuditVerbosity] filtering, nothing else.
  final AuditSeverity severity;

  /// The CXP peer id of the instance that recorded it, when there is one.
  ///
  /// Four products on one machine write to one file, and "which window did
  /// this" is otherwise unanswerable.
  final String? peerId;

  /// Structured detail. Whatever the product's kind defines.
  ///
  /// **Values must be JSON-encodable.** [toJson] does not sanitise: a value
  /// that cannot be encoded is a programming error at the call site, and
  /// silently dropping it would make the log lie.
  final Map<String, Object?> payload;

  /// The JSON object written as one JSONL line.
  ///
  /// Field order is fixed and the first field is always the timestamp, so that
  /// `sort` over a rotated set of files orders them correctly and `grep` over a
  /// live one stays readable.
  Map<String, Object?> toJson() => <String, Object?>{
    'ts': timestamp.toUtc().toIso8601String(),
    'product': product,
    'kind': kind,
    'severity': severity.name,
    if (peerId case final String id) 'peer': id,
    if (payload.isNotEmpty) 'payload': payload,
  };

  /// This event as the exact line a JSONL sink writes, newline included.
  String toJsonLine() => '${jsonEncode(toJson())}\n';
}
