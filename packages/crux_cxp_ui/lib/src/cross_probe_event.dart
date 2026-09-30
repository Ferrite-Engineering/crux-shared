// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';

/// Whether a [CrossProbeEvent] records something this app sent or received.
///
/// Lifecycle events (a peer connecting or disconnecting) carry no direction —
/// [CrossProbeEvent.direction] is null for those.
enum CrossProbeEventDirection {
  /// A message this app sent (a targeted `sendTo` or a broadcast).
  outbound,

  /// A message this app received from a peer.
  inbound,
}

/// The semantic category of a [CrossProbeEvent].
///
/// Richer than a raw wire `kind` string: it folds the sent/received direction
/// into the category so the panel can render each with its own icon and label
/// without re-deriving it. [CrossProbeEvent.messageKind] still carries the
/// underlying `CxpMessageKind` when one applies, for a precise tooltip.
enum CrossProbeEventKind {
  /// A peer completed its handshake and is now connected.
  peerConnected,

  /// A previously-connected peer went away.
  peerDisconnected,

  /// This app sent a `notify_selection` to a peer.
  selectionSent,

  /// This app received a `notify_selection` from a peer.
  selectionReceived,

  /// This app sent a `request_highlight` to a peer.
  highlightSent,

  /// This app received a `request_highlight` from a peer.
  highlightReceived,

  /// A `request_open_artifact` was exchanged — a peer asked this
  /// app to open a design artifact, or this app asked a peer to.
  openArtifact,

  /// Any other traffic, distinguished by [CrossProbeEvent.messageKind].
  other,
}

/// A single entry in the shared cross-probe panel's rolling event buffer.
///
/// This is the app-agnostic superset of every product's per-app event-log
/// entry: it adds the event categories (selection *received* and
/// *open-artifact*) that the divergent per-app logs were missing, and keeps the
/// value pure Dart (no Flutter dependency) so it can be constructed off the UI
/// thread and, if ever needed, hoisted into `crux_cxp`.
@immutable
class CrossProbeEvent {
  /// Creates a cross-probe event.
  const CrossProbeEvent({
    required this.kind,
    required this.peerLabel,
    required this.timestamp,
    this.direction,
    this.summary,
    this.messageKind,
  });

  /// Convenience constructor for a peer-connected lifecycle event.
  CrossProbeEvent.peerConnected({
    required this.peerLabel,
    DateTime? timestamp,
  }) : kind = CrossProbeEventKind.peerConnected,
       direction = null,
       summary = null,
       messageKind = null,
       timestamp = timestamp ?? DateTime.now();

  /// Convenience constructor for a peer-disconnected lifecycle event.
  CrossProbeEvent.peerDisconnected({
    required this.peerLabel,
    DateTime? timestamp,
  }) : kind = CrossProbeEventKind.peerDisconnected,
       direction = null,
       summary = null,
       messageKind = null,
       timestamp = timestamp ?? DateTime.now();

  /// The semantic category, driving the panel's icon and label.
  final CrossProbeEventKind kind;

  /// Whether the event was inbound or outbound. Null for lifecycle events
  /// (connect / disconnect) that have no direction.
  final CrossProbeEventDirection? direction;

  /// Human-readable peer label — typically the peer's `productName`, or
  /// `'(broadcast)'` for an untargeted outbound broadcast.
  final String peerLabel;

  /// When the event happened, in local time.
  final DateTime timestamp;

  /// Optional one-line gloss rendered next to the label (e.g. the selected
  /// signal's path, or the design/artifact a `request_open_artifact` named).
  final String? summary;

  /// The underlying `CxpMessageKind` wire discriminator when one applies
  /// (e.g. [CxpMessageKind.notifySelection]); null for lifecycle events.
  final String? messageKind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CrossProbeEvent &&
          other.kind == kind &&
          other.direction == direction &&
          other.peerLabel == peerLabel &&
          other.timestamp == timestamp &&
          other.summary == summary &&
          other.messageKind == messageKind);

  @override
  int get hashCode =>
      Object.hash(kind, direction, peerLabel, timestamp, summary, messageKind);

  @override
  String toString() =>
      'CrossProbeEvent(${kind.name}'
      '${direction == null ? '' : ' ${direction!.name}'}, '
      'peer=$peerLabel, summary=$summary)';
}
