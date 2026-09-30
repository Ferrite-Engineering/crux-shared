// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_audit/src/audit_event.dart';
import 'package:meta/meta.dart';

/// Where audit events go.
///
/// Deliberately narrow. An organization that wants forwarding points its
/// existing log shipper at the file — there is **no syslog transport, no
/// webhook and no SIEM connector**, and none is planned. The interface is
/// shaped so that a syslog sink would be an afternoon if someone actually asks
/// for one, which is the stated bar; it is not an invitation to write one now.
abstract class AuditSink {
  /// Record [event], or drop it if this sink's verbosity excludes it.
  ///
  /// **Never throws.** A product that crashed because it could not write an
  /// audit line would be worse than one that was never audited — see
  /// [AuditSinkHealth].
  Future<void> record(AuditEvent event);

  /// Flush anything buffered and release the handle.
  Future<void> close();

  /// Whether this sink is currently able to write, and why not if it is not.
  AuditSinkHealth get health;
}

/// Whether a sink is writing, and what went wrong if it is not.
///
/// ### Why this exists at all
///
/// Two things had to be settled by the implementation. This is the first: what
/// happens when the sink cannot write — disk full, path not writable,
/// permissions.
///
/// Neither obvious answer is right. **Crashing the product is wrong**: the user
/// is in the middle of debugging a waveform and the audit log is not what they
/// are doing. **Failing silently is worse**: an audit log that quietly stopped
/// is indistinguishable from one that recorded nothing because nothing
/// happened, and it is discovered during the investigation it was supposed to
/// support.
///
/// So: the sink degrades, keeps the application running, and makes the failure
/// **observable and loud in the one place that can act on it** — the host reads
/// [AuditSink.health] and surfaces it. `unhealthy` is a state a settings panel
/// shows and an administrator can be told about; it is never a state the app
/// hides.
///
/// The first failure is also recorded to the process log, once, so that a
/// support bundle carries it even if nobody looked at the panel.
@immutable
class AuditSinkHealth {
  /// Creates a health state.
  const AuditSinkHealth({required this.writable, this.detail, this.since});

  /// A sink that has stopped writing, because of [detail], since [since].
  const AuditSinkHealth.failed(String this.detail, DateTime this.since)
    : writable = false;

  /// The sink is writing normally.
  static const AuditSinkHealth healthy = AuditSinkHealth(writable: true);

  /// Whether events are reaching their destination.
  final bool writable;

  /// Why not, for a human. Null when [writable].
  final String? detail;

  /// When it first stopped being writable. Null when [writable].
  final DateTime? since;
}

/// A sink that drops everything.
///
/// The default in every product until an administrator configures a path, and
/// the honest one: auditing is off, and asking whether it is healthy says yes,
/// because a sink that was never asked to write has not failed.
class NoopAuditSink implements AuditSink {
  /// Creates the inert sink.
  const NoopAuditSink();

  @override
  Future<void> record(AuditEvent event) async {}

  @override
  Future<void> close() async {}

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;
}
