// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_audit/src/audit_event.dart';
import 'package:crux_audit/src/audit_sink.dart';
import 'package:path/path.dart' as p;

/// An append-only JSON-lines sink.
///
/// One event per line, newline-terminated, timestamp first. That is the whole
/// format, chosen because every log shipper already reads it and because `grep`
/// and `sort` work on it without a tool from us.
///
/// ### Rotation is the organization's, and this is what that costs
///
/// The decision: **this sink does not rotate.** An
/// organization that turns on audit logging already runs logrotate, or an agent
/// that does the same thing, and a second rotation policy fighting theirs is
/// worse than none. What this package owes them is not to break when theirs
/// runs.
///
/// **So it opens the file, appends one line, and closes — per event.** No
/// handle is held between writes, which is what makes every rotation scheme
/// work with no detection logic at all: after `mv`, the next event creates a
/// fresh file at the path; after copy-truncate, the next event appends at zero.
///
/// The cost is one open/close per event, and it is the right trade here. Audit
/// events are human-paced by construction — a waiver created, a decoder
/// activated, a licence tier changed — not a hot loop, and correctness under
/// somebody else's logrotate is worth far more than the syscalls.
///
/// A held handle was tried first and is instructive about why this is not
/// over-caution. Two separate defects appeared, both invisible without a test
/// that actually rotates: `openWrite` is lazy, so stamping the file's identity
/// straight after opening records the identity of a file that does not exist
/// yet — and after a rotation the path is *also* absent, so the staleness check
/// compared null to null, saw no change, and appended into an unlinked inode
/// forever. Fixing that surfaced the second: an `IOSink` holds its own write
/// offset, so flushing it after the file was truncated wrote at the old
/// position and left a run of NUL bytes that broke JSON parsing of the whole
/// file.
///
/// - **Appends only.** The sink never rewrites, never seeks backwards, and
///   never deletes. A file rotated out from under it belongs to the shipper.
/// - **`maxBytes`, when set, is a SAFETY VALVE and not a rotation policy.** It
///   stops an unattended machine filling its disk, by refusing to grow the file
///   further and reporting itself unhealthy. It does not roll, rename or
///   delete anything, because deleting an audit log is not this package's
///   decision to make.
///
/// ### Failure
///
/// Every write path is guarded. A failure degrades the sink — see
/// [AuditSinkHealth] — and is reported once to the process log; it never
/// throws into the caller and never takes the application down.
class JsonlAuditSink implements AuditSink {
  /// Creates a sink appending to [path].
  ///
  /// The parent directory is created if missing. Nothing is opened until the
  /// first recorded event, so a configured-but-unused sink leaves no file.
  JsonlAuditSink({
    required this.path,
    this.verbosity = AuditVerbosity.normal,
    this.maxBytes,
    void Function(String message)? onDiagnostic,
  }) : _onDiagnostic = onDiagnostic ?? _defaultDiagnostic;

  /// Absolute path of the JSONL file.
  final String path;

  /// How much is recorded.
  final AuditVerbosity verbosity;

  /// Refuse to grow the file beyond this many bytes. Null means no cap.
  ///
  /// A safety valve, not rotation — see the class doc.
  final int? maxBytes;

  final void Function(String message) _onDiagnostic;

  AuditSinkHealth _health = AuditSinkHealth.healthy;
  bool _reportedFailure = false;
  bool _closed = false;

  @override
  AuditSinkHealth get health => _health;

  @override
  Future<void> record(AuditEvent event) async {
    if (_closed || !verbosity.records(event.severity)) return;
    try {
      final file = File(path);
      final parent = Directory(p.dirname(path));
      if (!parent.existsSync()) parent.createSync(recursive: true);

      final cap = maxBytes;
      if (cap != null && file.existsSync() && file.lengthSync() >= cap) {
        _degrade(
          'audit log has reached its $cap-byte cap and will not grow further; '
          'rotate or archive $path',
        );
        return;
      }

      // Open, append, close. See the class doc for why no handle is held.
      file.writeAsStringSync(event.toJsonLine(), mode: FileMode.append);

      if (!_health.writable) {
        // It came back — a full disk was cleared, a permission was fixed, an
        // administrator archived the file that had hit the cap.
        _health = AuditSinkHealth.healthy;
        _reportedFailure = false;
      }
    } on Object catch (error) {
      _degrade('$error');
    }
  }

  void _degrade(String detail) {
    if (_health.writable) {
      _health = AuditSinkHealth.failed(detail, DateTime.now().toUtc());
    }
    if (!_reportedFailure) {
      _reportedFailure = true;
      // Once, so a support bundle carries it even if nobody opened the panel —
      // and only once, so a full disk does not produce a second log that fills
      // whatever is left of it.
      _onDiagnostic('crux_audit: cannot write $path — $detail');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

void _defaultDiagnostic(String message) {
  stderr.writeln(message);
}
