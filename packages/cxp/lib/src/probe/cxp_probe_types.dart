// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:cxp/src/element_id.dart';
import 'package:cxp/src/messages/highlight.dart';
import 'package:cxp/src/messages/open_source.dart';
import 'package:cxp/src/peer_identity.dart';
import 'package:cxp/src/stream_coordinate.dart';
import 'package:meta/meta.dart';

/// The prefix of the capability string a peer uses to say which element
/// kinds its `request_highlight` handler honours: `cxp.accepts:<kind>`
/// (CXP §8.1).
const String cxpAcceptsCapabilityPrefix = 'cxp.accepts:';

/// The `cxp.accepts:<kind>` capability string for [kind].
String cxpAcceptsCapability(ElementKind kind) =>
    '$cxpAcceptsCapabilityPrefix${kind.name}';

/// A CXP peer a `CxpProbe` is connected to.
///
/// A snapshot of the identity the peer announced in its handshake. Two peers
/// are equal when they have the same `peerId`, so a value survives being
/// kept in a set or compared with one taken later.
@immutable
class CxpProbePeer {
  /// Creates a peer record for [identity].
  const CxpProbePeer(this.identity);

  /// The identity the peer announced in its handshake.
  final PeerIdentity identity;

  /// The peer's stable identifier, unique among running peers.
  String get peerId => identity.peerId;

  /// The product name the peer announced, as it wrote it (the Crux apps
  /// announce lower case names).
  String get productName => identity.productName;

  /// The product version the peer announced.
  String get productVersion => identity.productVersion;

  /// The design the peer's active window has open, when it said (display
  /// text only).
  String? get activeDocument => identity.activeDocument;

  /// Whether this peer is the product called [product], ignoring case.
  bool isProduct(String product) =>
      identity.productName.toLowerCase() == product.toLowerCase();

  /// Whether the peer's highlight handler honours [kind].
  ///
  /// CXP §8.1: a sender **SHOULD** send a peer only the kinds it lists in
  /// its `cxp.accepts:<kind>` capabilities, and a peer that lists none is
  /// sent whatever the sender would send a peer it knows nothing about.
  /// This is that rule, and it is advice, not a contract: a peer
  /// acknowledges every request it accepts, including one it did not
  /// advertise.
  bool accepts(ElementKind kind) {
    var advertisesAny = false;
    for (final capability in identity.capabilities) {
      if (!capability.startsWith(cxpAcceptsCapabilityPrefix)) continue;
      advertisesAny = true;
      if (capability.substring(cxpAcceptsCapabilityPrefix.length) ==
          kind.name) {
        return true;
      }
    }
    return !advertisesAny;
  }

  @override
  bool operator ==(Object other) =>
      other is CxpProbePeer && other.peerId == peerId;

  @override
  int get hashCode => peerId.hashCode;

  @override
  String toString() => 'CxpProbePeer($productName $productVersion, $peerId)';
}

/// How one peer answered one request.
enum CxpProbeOutcome {
  /// The peer acted on the request (`honored: true`).
  honored,

  /// The peer understood the request and did not act on it: an
  /// acknowledgement with `honored: false`, or an `error_response`. The
  /// reason is in [CxpProbeReply.reason]. This is a normal outcome, not a
  /// protocol failure: an element the peer has not loaded is declined, not
  /// an error (CXP §9.5).
  declined,

  /// The request was sent and no answer arrived within the timeout.
  unacknowledged,

  /// The request could not be sent: the link to the peer was gone.
  failed,
}

/// One peer's answer to one request, as `CxpProbe`'s send methods return it.
@immutable
class CxpProbeReply {
  /// Creates a reply.
  const CxpProbeReply({required this.peer, required this.outcome, this.reason});

  /// The peer that was asked.
  final CxpProbePeer peer;

  /// How it answered.
  final CxpProbeOutcome outcome;

  /// Why the request was declined or failed, in the peer's words when it
  /// gave them.
  final String? reason;

  /// Whether the peer acted on the request.
  bool get honored => outcome == CxpProbeOutcome.honored;

  @override
  String toString() =>
      'CxpProbeReply(${peer.productName}: ${outcome.name}'
      '${reason == null ? '' : ', $reason'})';
}

/// What a `CxpProbe` reports as it runs.
@immutable
sealed class CxpProbeEvent {
  const CxpProbeEvent();
}

/// A peer finished its handshake and can be sent requests.
final class CxpPeerJoined extends CxpProbeEvent {
  /// Creates the event.
  const CxpPeerJoined(this.peer);

  /// The peer that joined.
  final CxpProbePeer peer;

  @override
  String toString() => 'CxpPeerJoined($peer)';
}

/// A peer's link closed: it quit, crashed, or was stopped.
final class CxpPeerLeft extends CxpProbeEvent {
  /// Creates the event.
  const CxpPeerLeft(this.peer);

  /// The peer that left.
  final CxpProbePeer peer;

  @override
  String toString() => 'CxpPeerLeft($peer)';
}

/// A peer announced its selection (`notify_selection`).
///
/// Only peers a probe is subscribed to deliver these; by default a probe
/// subscribes to every selection.
final class CxpSelectionReceived extends CxpProbeEvent {
  /// Creates the event.
  const CxpSelectionReceived({
    required this.peer,
    required this.elements,
    this.displayName,
    this.coordinate,
    this.metadata = const <String, Object?>{},
  });

  /// The peer whose user made the selection.
  final CxpProbePeer peer;

  /// The selected elements, in the sender's own order. Empty when the peer
  /// cleared its selection (a retraction, CXP §9.1.2).
  final List<ElementId> elements;

  /// The sender's label for the selection, when it gave one.
  final String? displayName;

  /// Where within a decoded stream the selection is, when the sender said
  /// (CXP §9.9).
  final CxpStreamCoordinate? coordinate;

  /// The sender's free-form context. Keys this package does not know are
  /// kept as sent.
  final Map<String, Object?> metadata;

  /// Whether the peer cleared its selection.
  bool get isRetraction => elements.isEmpty;

  @override
  String toString() =>
      'CxpSelectionReceived(${peer.productName}: $elements'
      '${displayName == null ? '' : ', $displayName'})';
}

/// A peer sent this program a request (`request_highlight` or
/// `request_open_source`) over its link.
///
/// The probe has already answered it, through the [CxpProbeRequestHandler]
/// it was given or, when there is none, with `honored: false`.
final class CxpRequestReceived extends CxpProbeEvent {
  /// Creates the event.
  const CxpRequestReceived({
    required this.peer,
    required this.request,
    required this.result,
  });

  /// The peer that asked.
  final CxpProbePeer peer;

  /// The request: a `RequestHighlight` or a `RequestOpenSource`.
  final Object request;

  /// What the probe answered.
  final CxpHandlerResult result;

  @override
  String toString() =>
      'CxpRequestReceived(${peer.productName}: $request -> $result)';
}

/// An answer to a request a peer sent this program.
@immutable
class CxpHandlerResult {
  /// Creates a result.
  const CxpHandlerResult({required this.honored, this.reason});

  /// Acted on the request.
  const CxpHandlerResult.honored() : this(honored: true);

  /// Did not act on the request, saying why in [reason] when it can.
  const CxpHandlerResult.declined([String? reason])
    : this(honored: false, reason: reason);

  /// Whether the request was acted on.
  final bool honored;

  /// Why not, when [honored] is false.
  final String? reason;

  @override
  String toString() =>
      'CxpHandlerResult(${honored ? 'honored' : 'declined'}'
      '${reason == null ? '' : ': $reason'})';
}

/// What a program does when a peer asks it to show something.
///
/// A peer can only send a request to a program it is connected to, and a
/// probe is connected to the peers it dialled; a peer that lists the probe
/// among its connected peers may send it one (the Crux apps do, from their
/// Connected Peers list). Without a handler every request is declined with
/// a reason, which is the right answer for a program with no screen.
abstract interface class CxpProbeRequestHandler {
  /// A peer asked this program to bring [request]`.element` into view.
  FutureOr<CxpHandlerResult> highlight(
    CxpProbePeer from,
    RequestHighlight request,
  );

  /// A peer asked this program to open a source location.
  FutureOr<CxpHandlerResult> openSource(
    CxpProbePeer from,
    RequestOpenSource request,
  );
}
