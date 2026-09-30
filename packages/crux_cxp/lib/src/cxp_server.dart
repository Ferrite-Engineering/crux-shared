// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/src/cxp_auth_token.dart';
import 'package:crux_cxp/src/cxp_path_containment.dart';
import 'package:crux_cxp/src/element_id.dart';
import 'package:crux_cxp/src/line_framing.dart';
import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:crux_cxp/src/messages/decoder.dart';
import 'package:crux_cxp/src/messages/error_response.dart';
import 'package:crux_cxp/src/messages/hello.dart';
import 'package:crux_cxp/src/messages/open_artifact.dart';
import 'package:crux_cxp/src/messages/open_source.dart';
import 'package:crux_cxp/src/messages/subscribe.dart';
import 'package:crux_cxp/src/name_resolver.dart';
import 'package:crux_cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// Event emitted when a peer connects or disconnects from a [CxpServer].
@immutable
class PeerPresenceEvent {
  /// Creates a presence event.
  const PeerPresenceEvent({required this.peer, required this.connected});

  /// The remote peer whose presence changed.
  final PeerIdentity peer;

  /// True for a new connection; false for a disconnection.
  final bool connected;

  @override
  String toString() {
    final state = connected ? 'connected' : 'disconnected';
    return 'PeerPresenceEvent(${peer.peerId}, $state)';
  }
}

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

/// Abstract CXP peer-cross-probe server.
///
/// Concrete implementations include [LocalCxpServer] (TCP/JSON on
/// localhost) and the test [NoopCxpServer]. Each Crux product instantiates
/// one server per running process; the server publishes its presence via
/// the manifest (see `cxp_discovery.dart`) and dispatches inbound
/// messages.
abstract class CxpServer {
  /// Start listening on the configured port.
  Future<void> start();

  /// Stop the server and close every active peer connection.
  Future<void> stop();

  /// Broadcast a [message] to every currently-reachable peer whose
  /// subscription filter matches it.
  ///
  /// Delivery contract (normative for CXP implementations):
  ///
  /// * The primary broadcast path is **server-accepted subscribed peers**:
  ///   a peer receives gossip by dialing this server and sending a
  ///   `Subscribe`. The **symmetric dial is the normative topology** —
  ///   every CXP node runs a server plus a connector that dials each
  ///   discovered peer, so in the standard deployment each side receives
  ///   the other's broadcasts as a server-accepted subscriber. A
  ///   third-party tool that wants gossip must dial in and subscribe, not
  ///   merely accept this node's outbound connection.
  /// * Connector-attached links (peers this node dialed via
  ///   `CxpPeerConnector`, registered through [attachLinkedPeer]) are
  ///   primarily the **directed** route: [sendTo] replies and acks travel
  ///   back over the link. As a fallback for asymmetric topologies, a
  ///   linked peer that has sent a `Subscribe` over the link also receives
  ///   matching broadcasts; delivery is de-duplicated, so a symmetrically
  ///   connected peer gets each frame exactly once.
  /// * A peer that has never subscribed receives no broadcasts on either
  ///   route.
  void broadcast(CxpMessage message);

  /// Send a [message] to a specific peer identified by [peerId].
  ///
  /// Routes over the peer's inbound connection when it has dialed this
  /// server, otherwise over a connector-attached outbound link (see
  /// [attachLinkedPeer]) — so replies to link-injected messages return
  /// over the same link. Returns `true` if the peer was reachable on
  /// either route; `false` otherwise.
  bool sendTo(String peerId, CxpMessage message);

  /// Stream of inbound messages from all connected peers.
  ///
  /// This is the single dispatch stream a product's request handler
  /// subscribes to. It carries messages from **both** transport
  /// directions: frames read off inbound sockets this server accepted,
  /// and frames a `CxpPeerConnector` routes in from its outbound links
  /// via [injectInbound].
  Stream<InboundCxpMessage> get inbound;

  /// Stream of peer-presence events.
  ///
  /// Events fire on reachability transitions: `connected` when a peer
  /// first becomes reachable (inbound handshake or attached link),
  /// `disconnected` when its last route goes away.
  Stream<PeerPresenceEvent> get presence;

  /// Currently reachable peers (a snapshot at the time of the call).
  ///
  /// The union of peers with a completed inbound handshake and peers
  /// attached via [attachLinkedPeer], de-duplicated by peer ID.
  List<PeerIdentity> get connectedPeers;

  /// The local peer's identity as configured at construction.
  PeerIdentity get selfIdentity;

  /// The port the server is currently bound to, or `null` before start.
  int? get boundPort;

  /// Register an outbound link to [peer] as a route this server can send
  /// on.
  ///
  /// A `CxpPeerConnector` calls this after its outbound handshake with
  /// [peer] completes, passing the link's [send] function. From then on
  /// [sendTo] can reach the peer even when the peer has no inbound
  /// connection to this server — replies (acks) to messages that arrived
  /// via [injectInbound] return over the same link.
  void attachLinkedPeer(
    PeerIdentity peer,
    void Function(CxpMessage message) send,
  );

  /// Remove the outbound-link route to [peerId] registered by
  /// [attachLinkedPeer]. No-op when no such link is attached.
  void detachLinkedPeer(String peerId);

  /// Feed a message received outside this server's own accept loop into
  /// the [inbound] dispatch stream.
  ///
  /// A `CxpPeerConnector` calls this for every frame its outbound
  /// clients receive, so consumers observe one merged stream regardless
  /// of which side dialed.
  void injectInbound(InboundCxpMessage message);
}

/// Default no-op server. Drops every send; never emits any event.
///
/// Used as the registered default in open-core builds before a product
/// has opted into CXP. The Pro / open-core wiring replaces it with
/// [LocalCxpServer] when the user enables cross-probe.
@immutable
class NoopCxpServer implements CxpServer {
  /// Creates a Noop server.
  const NoopCxpServer({required this.selfIdentity});

  @override
  final PeerIdentity selfIdentity;

  @override
  int? get boundPort => null;

  @override
  List<PeerIdentity> get connectedPeers => const <PeerIdentity>[];

  @override
  Stream<InboundCxpMessage> get inbound =>
      const Stream<InboundCxpMessage>.empty();

  @override
  Stream<PeerPresenceEvent> get presence =>
      const Stream<PeerPresenceEvent>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void broadcast(CxpMessage message) {}

  @override
  bool sendTo(String peerId, CxpMessage message) => false;

  @override
  void attachLinkedPeer(
    PeerIdentity peer,
    void Function(CxpMessage message) send,
  ) {}

  @override
  void detachLinkedPeer(String peerId) {}

  @override
  void injectInbound(InboundCxpMessage message) {}
}

/// Concrete TCP/JSON CXP server bound to localhost.
///
/// Wire format: newline-delimited JSON envelopes. Each connection has a
/// short handshake — the connecting peer sends a [Hello], the server
/// replies with a [HelloAck], then the connection is dispatched as a
/// full-duplex CXP channel.
///
/// Single-isolate dispatch: every connection's read loop runs on the
/// main isolate. v1 throughput is modest (selection events are
/// human-driven), so the simplicity is the right trade.
class LocalCxpServer implements CxpServer {
  /// Creates a local TCP server.
  ///
  /// Pass [nameResolver] to translate inbound element references into
  /// product-local form. When unset, [IdentityNameResolver] is used so
  /// the server can be exercised without product-specific wiring.
  ///
  /// [authToken] is the token a dialling peer must present in its Hello
  /// (see [cxpProcessAuthToken] for what it is and is not); it defaults to
  /// the process token, which `CxpManifestWriter` publishes by default, so
  /// the two need no wiring between them. [requireAuthToken] is the switch:
  /// `true` (the default) refuses a Hello without the token with
  /// `unauthorized` and closes; `false` accepts any Hello, which is the
  /// pre-1.2 behaviour and what a receiver that must interoperate with
  /// pre-1.2 diallers needs.
  ///
  /// [containment] is the rule applied to every path a peer asks this
  /// process to open, before the product sees the request — see
  /// [CxpPathContainment]. The default is the floor rule (absolute,
  /// well-formed); pass one with `roots` to enforce the spec's
  /// "directories the user has already opened".
  LocalCxpServer({
    required this.selfIdentity,
    NameResolver? nameResolver,
    this.host = '127.0.0.1',
    this.port = 0,
    this.maxLineLength = defaultCxpMaxLineLength,
    this.maxPendingWriteBytes = defaultCxpMaxPendingWriteBytes,
    String? authToken,
    this.requireAuthToken = true,
    this.containment = const CxpPathContainment(),
  }) : nameResolver = nameResolver ?? const IdentityNameResolver(),
       authToken = authToken ?? cxpProcessAuthToken;

  @override
  final PeerIdentity selfIdentity;

  /// The token a dialling peer must present in its Hello. Publish it in
  /// this peer's manifest (`CxpManifestWriter.authToken`); both default to
  /// [cxpProcessAuthToken].
  final String authToken;

  /// Whether a Hello that does not carry [authToken] is refused. See the
  /// constructor.
  final bool requireAuthToken;

  /// The rule every peer-supplied path is checked against before a
  /// `request_open_source` or `request_open_artifact` reaches the product.
  /// See [CxpPathContainment] and [_contain].
  final CxpPathContainment containment;

  /// Resolver used by handlers that need to map inbound [ElementId]s into
  /// local references. Exposed so tests and consumers can replace it.
  final NameResolver nameResolver;

  /// Bind host. Localhost by default.
  final String host;

  /// Requested bind port. `0` lets the OS pick a free port; the actual
  /// bound port is available via [boundPort] after [start] resolves.
  final int port;

  /// Upper bound on one newline-delimited frame; connections exceeding
  /// it are dropped. See [CappedLineSplitter].
  final int maxLineLength;

  /// Upper bound on un-flushed outbound bytes buffered for one peer.
  /// A peer that stops reading past this cap is disconnected rather than
  /// allowed to grow this process's heap. See
  /// [defaultCxpMaxPendingWriteBytes].
  final int maxPendingWriteBytes;

  ServerSocket? _server;
  final List<_PeerConnection> _peers = <_PeerConnection>[];

  /// The `message_id`s of the error_responses each peer has sent, most
  /// recent last and at most [_errorsRemembered] per peer, so [sendTo] can
  /// refuse to answer one with another. Forgotten when the peer goes.
  final Map<String, Set<String>> _errorsReceived = <String, Set<String>>{};

  /// How many of a peer's error_response ids [_errorsReceived] keeps. A
  /// product answers a message as it arrives, so the window only has to
  /// span the time a dispatch takes.
  static const int _errorsRemembered = 64;
  final Map<String, _LinkedPeer> _linkedPeers = <String, _LinkedPeer>{};
  // Not `final`: [stop] closes both controllers and [start] recreates
  // them, so a stop/start cycle (the user toggling CXP off and on in
  // settings) yields a working server rather than one that binds and
  // accepts but silently drops every message on the `isClosed` guards.
  StreamController<InboundCxpMessage> _inbound =
      StreamController<InboundCxpMessage>.broadcast();
  StreamController<PeerPresenceEvent> _presence =
      StreamController<PeerPresenceEvent>.broadcast();
  var _running = false;

  @override
  int? get boundPort => _server?.port;

  @override
  Stream<InboundCxpMessage> get inbound => _inbound.stream;

  @override
  Stream<PeerPresenceEvent> get presence => _presence.stream;

  @override
  List<PeerIdentity> get connectedPeers {
    final byId = <String, PeerIdentity>{};
    for (final peer in _peers) {
      final id = peer.identity;
      if (id != null) byId[id.peerId] = id;
    }
    for (final link in _linkedPeers.values) {
      byId.putIfAbsent(link.identity.peerId, () => link.identity);
    }
    return List.unmodifiable(byId.values);
  }

  @override
  Future<void> start() async {
    if (_running) return;
    // Bind BEFORE claiming to be running. Setting the flag first meant a
    // failed bind (port already in use) left `_running == true` with a
    // null `_server`, so every later start() short-circuited and reported
    // success against a server that was permanently dead.
    final s = await ServerSocket.bind(host, port);
    // A previous stop() closed the broadcast controllers; a restart needs
    // live ones or injectInbound / _onInbound silently drop everything.
    if (_inbound.isClosed) {
      _inbound = StreamController<InboundCxpMessage>.broadcast();
    }
    if (_presence.isClosed) {
      _presence = StreamController<PeerPresenceEvent>.broadcast();
    }
    _running = true;
    _server = s;
    s.listen(
      _onConnection,
      onError: (Object _) {},
      onDone: () {},
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    for (final peer in List<_PeerConnection>.from(_peers)) {
      await peer.close();
    }
    _peers.clear();
    _linkedPeers.clear();
    _errorsReceived.clear();
    await _server?.close();
    _server = null;
    await _inbound.close();
    await _presence.close();
  }

  @override
  void broadcast(CxpMessage message) {
    // Iterate a copy: a failed peer.send disconnects the peer, which
    // removes it from _peers mid-iteration.
    final deliveredTo = <String>{};
    for (final peer in List<_PeerConnection>.of(_peers)) {
      final id = peer.identity;
      if (id == null) continue;
      if (!peer.accepts(message)) continue;
      peer.send(message);
      deliveredTo.add(id.peerId);
    }
    // Also fan out over connector links. A peer this server only dialed
    // (attached via attachLinkedPeer, no inbound socket) would otherwise
    // never receive broadcast gossip — notify_selection then needed
    // symmetric dial-back. Route to each linked peer whose subscriptions
    // match, skipping any peer already served over an inbound connection so
    // a symmetrically-connected peer is not sent the frame twice.
    for (final link in List<_LinkedPeer>.of(_linkedPeers.values)) {
      if (deliveredTo.contains(link.identity.peerId)) continue;
      if (!link.accepts(message)) continue;
      link.send(message);
    }
  }

  /// Sends [message] to [peerId] — except an [ErrorResponse] that answers
  /// an `error_response` the peer sent, which is dropped (§9.8). A product
  /// that replies to every message it does not handle would otherwise
  /// answer a peer's error with its own, and two such peers would trade
  /// errors for as long as both run. Returns whether the peer is
  /// reachable, sent or not.
  @override
  bool sendTo(String peerId, CxpMessage message) {
    if (message is ErrorResponse &&
        (_errorsReceived[peerId]?.contains(message.inReplyTo) ?? false)) {
      return _isReachable(peerId);
    }
    for (final peer in List<_PeerConnection>.of(_peers)) {
      if (peer.identity?.peerId == peerId) {
        peer.send(message);
        return true;
      }
    }
    // No inbound connection from the peer — fall back to an outbound
    // link the connector attached, so replies to link-injected messages
    // return over the same link.
    final link = _linkedPeers[peerId];
    if (link != null) {
      link.send(message);
      return true;
    }
    return false;
  }

  @override
  void attachLinkedPeer(
    PeerIdentity peer,
    void Function(CxpMessage message) send,
  ) {
    final wasReachable = _isReachable(peer.peerId);
    _linkedPeers[peer.peerId] = _LinkedPeer(identity: peer, send: send);
    if (!wasReachable && !_presence.isClosed) {
      _presence.add(PeerPresenceEvent(peer: peer, connected: true));
    }
  }

  @override
  void detachLinkedPeer(String peerId) {
    final removed = _linkedPeers.remove(peerId);
    if (!_isReachable(peerId)) _errorsReceived.remove(peerId);
    if (removed != null && !_isReachable(peerId) && !_presence.isClosed) {
      _presence.add(
        PeerPresenceEvent(peer: removed.identity, connected: false),
      );
    }
  }

  /// Records [message]'s id when it is an error_response. See
  /// [_errorsReceived].
  void _noteError(InboundCxpMessage message) {
    if (message.message is! ErrorResponse) return;
    final ids = _errorsReceived.putIfAbsent(
      message.from.peerId,
      () => <String>{},
    )..add(message.envelope.messageId);
    if (ids.length > _errorsRemembered) ids.remove(ids.first);
  }

  @override
  void injectInbound(InboundCxpMessage message) {
    // Subscribe / Unsubscribe frames arriving over a connector link update
    // that linked peer's filter set rather than surfacing to the product's
    // handler — the same way the inbound _PeerConnection path consumes them
    // (see _PeerConnection._handle). Recording them here is what lets
    // broadcast fan out over the link with the peer's real filter applied.
    final body = message.message;
    final link = _linkedPeers[message.from.peerId];
    if (link != null) {
      if (body is Subscribe) {
        link.subscriptions = List.unmodifiable(body.subscriptions);
        return;
      }
      if (body is Unsubscribe) {
        link.subscriptions = const <CxpSubscription>[];
        return;
      }
    }
    // A link is a full-duplex channel: the requests a peer sends over the
    // socket WE dialled arrive here, not on the accept loop, and the
    // containment rule has to hold on both.
    _noteError(message);
    final admitted = _contain(message);
    if (admitted != null && !_inbound.isClosed) _inbound.add(admitted);
  }

  /// Applies [containment] to a request before it reaches the product.
  ///
  /// Returns the message to dispatch, or null when it was answered here:
  ///
  /// * a `request_open_source` whose `file_path` is refused is acknowledged
  ///   `honored: false` with the rule's reason (§9.7 requires an ack for
  ///   every request the receiver accepts, and a refusal is an ordinary
  ///   answer, not a protocol error) and never dispatched;
  /// * a `request_open_artifact` whose `path` hint is refused is dispatched
  ///   with the hint removed — the receiver is told to prefer its own
  ///   resolution and treat the hint as a fallback (§9.10), so a hint that
  ///   fails the rule is simply no fallback. The `design_id` still resolves
  ///   through the workspace store, which applies the same rule to what it
  ///   returns.
  ///
  /// The ack travels back the way the request came: over the peer's
  /// inbound socket when it dialled us, over the attached link otherwise —
  /// the same route the product's own acks take.
  InboundCxpMessage? _contain(InboundCxpMessage message) {
    final body = message.message;
    if (body is RequestOpenSource) {
      final reason = containment.refuse(body.filePath);
      if (reason == null) return message;
      sendTo(
        message.from.peerId,
        RequestOpenSourceAck(
          inReplyTo: message.envelope.messageId,
          honored: false,
          reason: reason,
        ),
      );
      return null;
    }
    if (body is RequestOpenArtifact) {
      final hint = body.path;
      if (hint == null || containment.allows(hint)) return message;
      return InboundCxpMessage(
        envelope: message.envelope,
        message: RequestOpenArtifact(
          designId: body.designId,
          artifactKind: body.artifactKind,
        ),
        from: message.from,
      );
    }
    return message;
  }

  /// Subscriptions the inbound-connected [peerId] has registered, for
  /// test observability. Empty when the peer is unknown or has none.
  @visibleForTesting
  List<CxpSubscription> debugSubscriptionsOf(String peerId) {
    for (final peer in _peers) {
      if (peer.identity?.peerId == peerId) return peer.subscriptions;
    }
    return const <CxpSubscription>[];
  }

  /// Un-flushed outbound bytes currently buffered for the inbound-connected
  /// [peerId], or `-1` when the peer is unknown. See
  /// [maxPendingWriteBytes].
  @visibleForTesting
  int debugPendingWriteBytesOf(String peerId) {
    for (final peer in _peers) {
      if (peer.identity?.peerId == peerId) return peer.pendingWriteBytes;
    }
    return -1;
  }

  /// Marks the connected peer [peerId] so that peer's next outbound
  /// send fails as if the socket had died underneath it.
  ///
  /// The failure disconnects the peer from inside the send path — that
  /// is, potentially while [broadcast] is iterating the peer list. Tests
  /// use this to pin the requirement that a mid-broadcast disconnect must
  /// not corrupt the iteration.
  @visibleForTesting
  void debugFailNextSendTo(String peerId) {
    for (final peer in _peers) {
      if (peer.identity?.peerId == peerId) {
        peer.debugFailNextSend = true;
      }
    }
  }

  bool _isReachable(String peerId) =>
      _linkedPeers.containsKey(peerId) ||
      _peers.any((p) => p.identity?.peerId == peerId);

  void _onConnection(Socket socket) {
    final peer = _PeerConnection(
      socket: socket,
      server: this,
    );
    _peers.add(peer);
    peer.start();
  }

  void _onPeerDisconnected(_PeerConnection peer) {
    _peers.remove(peer);
    final id = peer.identity;
    if (id != null && !_isReachable(id.peerId)) {
      _errorsReceived.remove(id.peerId);
    }
    // Presence is per-peer reachability, not per-socket: suppress the
    // disconnect event while another route (attached link or second
    // inbound connection) still reaches the peer.
    if (id != null && !_isReachable(id.peerId) && !_presence.isClosed) {
      _presence.add(PeerPresenceEvent(peer: id, connected: false));
    }
  }

  void _onPeerHello(_PeerConnection peer) {
    final id = peer.identity;
    if (id == null) return;
    final reachableElsewhere =
        _linkedPeers.containsKey(id.peerId) ||
        _peers.any(
          (p) => !identical(p, peer) && p.identity?.peerId == id.peerId,
        );
    if (!reachableElsewhere && !_presence.isClosed) {
      _presence.add(PeerPresenceEvent(peer: id, connected: true));
    }
  }

  void _onInbound(InboundCxpMessage message) {
    _noteError(message);
    final admitted = _contain(message);
    if (admitted != null && !_inbound.isClosed) _inbound.add(admitted);
  }
}

/// An outbound-link route registered via
/// [LocalCxpServer.attachLinkedPeer].
class _LinkedPeer {
  _LinkedPeer({required this.identity, required this.send});

  final PeerIdentity identity;
  final void Function(CxpMessage message) send;

  /// The remote peer's subscription filter set, as carried in the
  /// [Subscribe] frames it sends over the link and injected via
  /// [LocalCxpServer.injectInbound]. Empty until the peer subscribes, so a
  /// linked peer receives no broadcast before it has expressed interest —
  /// the same rule the inbound [_PeerConnection] path follows.
  List<CxpSubscription> subscriptions = const <CxpSubscription>[];

  bool accepts(CxpMessage message) {
    for (final sub in subscriptions) {
      if (sub.matches(message)) return true;
    }
    return false;
  }
}

/// A live socket connection to one peer. Owns the read loop, subscription
/// state, and write queue for that peer.
class _PeerConnection {
  _PeerConnection({required this.socket, required this.server});

  final Socket socket;
  final LocalCxpServer server;

  PeerIdentity? identity;
  List<CxpSubscription> _subscriptions = const <CxpSubscription>[];
  StreamSubscription<String>? _lineSub;
  var _closed = false;

  /// True once the socket can no longer accept writes. Distinct from
  /// [_closed], which is set at the *start* of teardown while the socket
  /// is still drainable. See [_write].
  var _socketDead = false;

  /// When set, the next [send] simulates a synchronous socket-write
  /// failure instead of writing. See
  /// [LocalCxpServer.debugFailNextSendTo].
  bool debugFailNextSend = false;

  /// Outbound bytes queued for the socket sink but not yet flushed.
  int pendingWriteBytes = 0;

  /// Serializes outbound writes so no two `write`/`flush`/`close` calls
  /// on [socket] ever overlap. See [_write].
  Future<void> _writeChain = Future<void>.value();

  List<CxpSubscription> get subscriptions => _subscriptions;

  void start() {
    // `socket.write` is an IOSink write: it never throws synchronously,
    // so the try/catch around it can only ever catch the deliberate test
    // fault. A real write to a dead peer surfaces here, on `done`. Without
    // this listener the SocketException escaped to
    // Zone.handleUncaughtError and the peer lingered in `_peers` until the
    // read side happened to notice.
    unawaited(
      socket.done.then<void>(
        (_) {
          _socketDead = true;
          _disconnect();
        },
        onError: (Object _) {
          _socketDead = true;
          _disconnect();
        },
      ),
    );
    _lineSub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(CappedLineSplitter(maxLineLength: server.maxLineLength))
        .listen(
          _onLine,
          onError: (Object _) => _disconnect(),
          onDone: _disconnect,
          cancelOnError: false,
        );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _lineSub?.cancel();
    // Let any in-flight write finish flushing first: closing the sink
    // while a flush is pending throws StateError, and the frame we are
    // usually closing right after (an ErrorResponse for an unsupported
    // version) must reach the peer before the FIN does.
    try {
      await _writeChain;
    } on Object {
      // A failed write is already handled by _write's own catch.
    }
    try {
      await socket.close();
    } on Object {
      // Socket already closed.
    }
    _socketDead = true;
  }

  bool accepts(CxpMessage message) {
    for (final sub in _subscriptions) {
      if (sub.matches(message)) return true;
    }
    return false;
  }

  void send(CxpMessage message) {
    if (_closed) return;
    final envelope = CxpEnvelope(
      messageId: _newMessageId(),
      from: server.selfIdentity.peerId,
      kind: message.kind,
      payload: message.toJson(),
    );
    if (debugFailNextSend) {
      debugFailNextSend = false;
      _disconnect();
      return;
    }
    _write(envelope.encodeLine());
  }

  void _sendEnvelope(CxpEnvelope envelope) {
    if (_closed) return;
    _write(envelope.encodeLine());
  }

  /// Fire-and-forget write with outbound backpressure accounting.
  ///
  /// The write itself cannot fail synchronously (see [start]); what this
  /// guards is unbounded buffering. A frame is counted in flight from the
  /// moment it is queued until the sink reports it flushed, and a peer
  /// that lets the backlog exceed
  /// [LocalCxpServer.maxPendingWriteBytes] is disconnected — the outbound
  /// mirror of the inbound [CappedLineSplitter] cap.
  ///
  /// Writes are serialized through [_writeChain] rather than flushed
  /// individually: `IOSink.flush` marks the sink bound for its duration,
  /// so a `write` or `close` overlapping a pending flush throws
  /// `StateError` — which, swallowed by [close]'s catch, would leave the
  /// socket open forever.
  void _write(String line) {
    if (_closed) return;
    final bytes = line.length;
    if (pendingWriteBytes + bytes > server.maxPendingWriteBytes) {
      _disconnect();
      return;
    }
    pendingWriteBytes += bytes;
    _writeChain = _writeChain
        .then((_) async {
          // Gated on socket liveness, NOT on `_closed`: the read loop
          // queues a final frame (an ErrorResponse for an unsupported
          // version) and then immediately disconnects, and that frame
          // must still reach the peer — `close()` drains this chain
          // before closing the socket. But once the socket is actually
          // dead, writing to it trips a dart:io assertion, so everything
          // still queued behind the failure is dropped instead.
          if (_socketDead) return;
          try {
            socket.write(line);
            await socket.flush();
          } on Object {
            _socketDead = true;
            _disconnect();
          }
        })
        .whenComplete(() => pendingWriteBytes -= bytes);
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    CxpEnvelope envelope;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        if (decoded is Map) {
          envelope = CxpEnvelope.fromJson(decoded.cast<String, Object?>());
        } else {
          _rejectFrame('Top-level JSON value is not an object.');
          return;
        }
      } else {
        envelope = CxpEnvelope.fromJson(decoded);
      }
    } on FormatException catch (e) {
      _rejectFrame(e.message);
      return;
    }

    // §9.8: an error_response is never answered with one, whatever is wrong
    // with it — two peers that did could answer each other forever. Each
    // error reply below is skipped for it; what else happens is unchanged.
    final isError = envelope.kind == CxpMessageKind.errorResponse;

    if (!isCompatibleCxpVersion(envelope.cxpVersion)) {
      // Major-version mismatch: error AND close, per the policy on
      // [cxpProtocolVersion]. Minor differences pass the check above. For
      // an error_response the close alone is the rejection.
      if (!isError) {
        _sendError(
          code: CxpErrorCode.unsupportedVersion,
          message: 'Unsupported cxp_version "${envelope.cxpVersion}".',
          inReplyTo: envelope.messageId,
        );
      }
      _disconnect();
      return;
    }

    final CxpMessage? message;
    try {
      message = decodeCxpMessage(envelope.kind, envelope.payload);
    } on FormatException catch (e) {
      // Known kind, undecodable payload — report rather than letting the
      // exception escape the read loop. An error_response that does not
      // decode is dropped unanswered.
      if (!isError) {
        _sendError(
          code: CxpErrorCode.malformedPayload,
          message: e.message,
          inReplyTo: envelope.messageId,
        );
      }
      return;
    }
    if (message == null) {
      _sendError(
        code: CxpErrorCode.unknownKind,
        message: 'Unknown message kind "${envelope.kind}".',
        inReplyTo: envelope.messageId,
      );
      return;
    }

    if (identity == null && message is! Hello) {
      // An error_response before the handshake is dropped: it cannot be
      // dispatched, and it must not be answered.
      if (!isError) {
        _sendError(
          code: CxpErrorCode.handshakeRequired,
          message: 'A Hello message is required before any other traffic.',
          inReplyTo: envelope.messageId,
        );
      }
      return;
    }

    if (message is Hello) {
      if (server.requireAuthToken &&
          !cxpAuthTokensMatch(message.token, server.authToken)) {
        // The peer could reach the port but not the manifest that names
        // it — or reached a stale one. Either way it has not shown what
        // this server requires, so it is told which requirement failed
        // (never what the token is) and dropped before it is a peer: no
        // identity is recorded, so no presence event and no dispatch.
        _sendError(
          code: CxpErrorCode.unauthorized,
          message:
              'A hello to this peer must carry the token published in its '
              'manifest.',
          inReplyTo: envelope.messageId,
        );
        _disconnect();
        return;
      }
      identity = message.identity;
      _sendEnvelope(
        CxpEnvelope(
          messageId: _newMessageId(),
          from: server.selfIdentity.peerId,
          kind: HelloAck(
            identity: server.selfIdentity,
            inReplyTo: envelope.messageId,
          ).kind,
          payload: HelloAck(
            identity: server.selfIdentity,
            inReplyTo: envelope.messageId,
          ).toJson(),
        ),
      );
      server._onPeerHello(this);
      return;
    }

    if (message is Subscribe) {
      _subscriptions = List.unmodifiable(message.subscriptions);
      return;
    }

    if (message is Unsubscribe) {
      _subscriptions = const <CxpSubscription>[];
      return;
    }

    if (message is Goodbye) {
      _disconnect();
      return;
    }

    server._onInbound(
      InboundCxpMessage(
        envelope: envelope,
        message: message,
        from: identity!,
      ),
    );
  }

  /// Answers a frame that is not a CXP envelope with `malformed_envelope`
  /// and closes the connection.
  ///
  /// Closing — rather than answering and reading on, which is what this
  /// path used to do — is what makes a well-known port safe to leave
  /// listening. Every product binds a fixed default (54322–54325), and a
  /// web page can `fetch()` any of them: a `text/plain` POST needs no
  /// preflight, so the browser writes the HTTP request straight onto the
  /// socket. Its request line and headers are frames this decoder rejects;
  /// its body is whatever the page chose, newline-delimited JSON included.
  /// A server that answered each bad frame and kept going would then
  /// dispatch that body as a handshake and a stream of requests — from any
  /// site the user had open, blind, since the page cannot read the reply.
  /// Chrome's Local Network Access gate mitigates this; Firefox and Safari
  /// do not. An HTTP request cannot begin with a JSON object, so dropping
  /// the connection on the first frame that is not one ends the vector
  /// before the body is reached.
  ///
  /// The same rule costs a conforming peer nothing: it never sends a frame
  /// that is not an envelope. The frames that *are* envelopes but carry an
  /// undecodable payload (`malformed_payload`) or an unknown kind
  /// (`unknown_kind`) still leave the connection open, as §6.1 requires.
  void _rejectFrame(String message) {
    _sendError(
      code: CxpErrorCode.malformedEnvelope,
      message: message,
      inReplyTo: '',
    );
    _disconnect();
  }

  void _sendError({
    required String code,
    required String message,
    required String inReplyTo,
  }) {
    final body = ErrorResponse(
      code: code,
      message: message,
      inReplyTo: inReplyTo,
    );
    _sendEnvelope(
      CxpEnvelope(
        messageId: _newMessageId(),
        from: server.selfIdentity.peerId,
        kind: body.kind,
        payload: body.toJson(),
      ),
    );
  }

  void _disconnect() {
    if (_closed) return;
    server._onPeerDisconnected(this);
    unawaited(close());
  }
}

int _messageCounter = 0;

String _newMessageId() {
  _messageCounter++;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return 'm-$stamp-$_messageCounter';
}
