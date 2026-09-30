// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The shared audit-event envelope, the sink seam, and an append-only JSONL
/// sink.
///
/// **The envelope is shared; the event kinds are not.** A kind is a plain
/// string a product registers, because what is worth recording is a product's
/// own business — and a shared enum would need editing in `crux-shared` every
/// time any one of four products learned a new event.
///
/// What is deliberately absent: **no syslog transport, no webhook, no SIEM
/// connector.** An organization that wants forwarding points its existing log
/// shipper at the file (<https://edacrux.app/audit-log#shipping>), and that is
/// the whole of it.
///
/// Pure Dart permanently: both products' headless Pro CLIs write audit events.
library;

export 'src/audit_event.dart';
export 'src/audit_sink.dart';
export 'src/jsonl_audit_sink.dart';
export 'src/shared_audit_kinds.dart';
