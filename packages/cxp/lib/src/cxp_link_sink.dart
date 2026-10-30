// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:cxp/src/messages/cxp_message.dart';
import 'package:cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// An inbound message paired with the peer that sent it.
@immutable
class InboundCxpMessage {
  /// Creates a record of an inbound message.
  const InboundCxpMessage({
    required this.envelope,
    required this.message,
    required this.from,
  });

  /// The decoded envelope as it was received on the wire.
  final CxpEnvelope envelope;

  /// The concrete decoded message body.
  final CxpMessage message;

  /// Identity of the sending peer.
  final PeerIdentity from;
}

/// Where a `CxpPeerConnector` delivers what its outbound links carry.
///
/// An outbound link is a full-duplex channel: the remote peer answers and
/// gossips back over it. The connector hands each link to a sink, which is
/// whatever owns the local dispatch (a listening peer's server, or the
/// `CxpProbe` client of a program that listens for nothing).
abstract interface class CxpLinkSink {
  /// Register an outbound link to [peer] as a route that can be sent on.
  ///
  /// The connector calls this after its handshake with [peer] completes,
  /// passing the link's [send] function. Replies to messages that arrived
  /// through [injectInbound] return over the same link.
  void attachLinkedPeer(
    PeerIdentity peer,
    void Function(CxpMessage message) send,
  );

  /// Remove the outbound-link route to [peerId] registered by
  /// [attachLinkedPeer]. No-op when no such link is attached.
  void detachLinkedPeer(String peerId);

  /// Feed a message received on an outbound link into the local dispatch.
  ///
  /// The connector calls this for every frame an outbound link receives, so
  /// the sink sees one stream whichever side dialled.
  void injectInbound(InboundCxpMessage message);
}
