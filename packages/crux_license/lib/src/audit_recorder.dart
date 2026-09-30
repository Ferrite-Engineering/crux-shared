// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/src/policy_binding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Records audit events for one product, stamping the envelope fields the
/// product would otherwise repeat at every call site.
///
/// ### Why this exists rather than four copies of three lines
///
/// [cruxAuditSinkProvider] answers *where* events go. It does not answer
/// *who is recording*, and every emitter needs to say so: [AuditEvent]
/// requires a `product`, wants the CXP `peerId` (four products on one machine
/// write to one file, and "which window did this" is otherwise unanswerable),
/// and needs a UTC timestamp. Written at the call site that is four lines of
/// ceremony around one fact, repeated at every site in four products, and the
/// first thing to drift is the one field that makes a shared file readable.
///
/// So the same argument that put the sink binding in `crux-shared` puts this
/// here: the wiring is identical everywhere, and only the *kinds* are a
/// product's own business.
///
/// ### Fire-and-forget, deliberately
///
/// [record] returns `void`. An audit write must not turn a synchronous call
/// site — a waiver being deleted, a session being saved — into an asynchronous
/// one, because that changes the shape of the code being audited to suit the
/// auditing. It is safe: [AuditSink.record] never throws by contract, and a
/// sink that cannot write degrades to `unhealthy` and says so through
/// [AuditSink.health] rather than by raising.
///
/// A caller that genuinely needs the write to have landed — a CLI about to
/// exit, where the process may end before the append completes — uses
/// [recordAndFlush].
class CruxAuditRecorder {
  /// Creates a recorder writing to [sink] on behalf of [productId].
  ///
  /// [onDiagnostic] receives the one message a contract-violating sink
  /// produces; it defaults to stderr, matching [JsonlAuditSink].
  CruxAuditRecorder({
    required this.sink,
    required this.productId,
    this.peerId,
    void Function(String message)? onDiagnostic,
  }) : _onDiagnostic = onDiagnostic ?? _defaultDiagnostic;

  final void Function(String message) _onDiagnostic;

  /// Where events go. [NoopAuditSink] until an administrator configures
  /// `suite.audit.path`.
  final AuditSink sink;

  /// The product id written into every envelope — `wavecrux`, `netcrux`,
  /// `lintcrux`, `simcrux`. The same id the product's policy namespace uses,
  /// so one file can be filtered by product with the same string an
  /// administrator already typed into `.crux-policy.json`.
  final String productId;

  /// The CXP peer id of this instance, when the product has one.
  final String? peerId;

  /// Records [kind] with [payload]. Never throws, never blocks.
  ///
  /// [payload] values must be JSON-encodable — [AuditEvent.toJson] does not
  /// sanitise, because silently dropping a value would make the log lie.
  ///
  /// A sink that throws is violating [AuditSink.record]'s contract, and the
  /// error is caught here rather than left to reach the zone. `unawaited`
  /// alone does not contain it: the rejected future becomes an unhandled
  /// asynchronous error, which in a Flutter app is a red screen raised by the
  /// audit log — precisely the failure mode `AuditSinkHealth` exists to avoid,
  /// arriving through the one path that bypassed it. Caught, reported once to
  /// [_onDiagnostic] so a support bundle carries it, and dropped: the user is
  /// in the middle of their work and the audit log is not what they are doing.
  void record(
    String kind, {
    AuditSeverity severity = AuditSeverity.info,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? at,
  }) {
    unawaited(
      recordAndFlush(
        kind,
        severity: severity,
        payload: payload,
        at: at,
      ).catchError(_reportViolation),
    );
  }

  void _reportViolation(Object error, StackTrace stack) {
    if (_reportedViolation) return;
    _reportedViolation = true;
    _onDiagnostic(
      'crux_audit: the configured AuditSink threw, which its contract '
      'forbids. Audit events from this process may be missing. Cause: $error',
    );
  }

  static bool _reportedViolation = false;

  /// [record], awaitable — for a CLI that may exit before the append lands.
  Future<void> recordAndFlush(
    String kind, {
    AuditSeverity severity = AuditSeverity.info,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? at,
  }) {
    return sink.record(
      AuditEvent(
        timestamp: (at ?? DateTime.now()).toUtc(),
        product: productId,
        kind: kind,
        severity: severity,
        peerId: peerId,
        payload: payload,
      ),
    );
  }
}

/// The product id stamped into this installation's audit events.
///
/// Overridden by every product with its own `<Product>PolicyKeys.productId`.
/// The unhelpful default is deliberate and visible: an event tagged
/// `unconfigured` in a shared file is a wiring bug an administrator can
/// actually report, where a plausible-looking default would be a lie nobody
/// notices.
final cruxAuditProductIdProvider = Provider<String>(
  (ref) => 'unconfigured',
  name: 'cruxAuditProductIdProvider',
);

/// This instance's CXP peer id, when the product has one.
///
/// Null by default. Overridden by products that run a CXP server, so a shared
/// audit file can distinguish two windows of the same product.
final cruxAuditPeerIdProvider = Provider<String?>(
  (ref) => null,
  name: 'cruxAuditPeerIdProvider',
);

/// The recorder every emitter in a product reads.
///
/// ```dart
/// ref.read(cruxAuditRecorderProvider).record(
///   LintCruxAuditKinds.waiverCreated,
///   payload: {'waiverId': id, 'ruleId': ruleId},
/// );
/// ```
final cruxAuditRecorderProvider = Provider<CruxAuditRecorder>(
  (ref) => CruxAuditRecorder(
    sink: ref.watch(cruxAuditSinkProvider),
    productId: ref.watch(cruxAuditProductIdProvider),
    peerId: ref.watch(cruxAuditPeerIdProvider),
  ),
  name: 'cruxAuditRecorderProvider',
);

void _defaultDiagnostic(String message) {
  stderr.writeln(message);
}
