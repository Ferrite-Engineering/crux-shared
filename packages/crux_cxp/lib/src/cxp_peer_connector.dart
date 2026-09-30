// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/src/cxp_client.dart';
import 'package:crux_cxp/src/cxp_discovery.dart';
import 'package:crux_cxp/src/cxp_server.dart';
import 'package:crux_cxp/src/messages/subscribe.dart';
import 'package:crux_cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// Whether [host] names this machine's loopback interface — the only kind
/// of host a CXP peer may be dialled at.
///
/// CXP is a same-machine protocol (spec §1.1, §4.1): a peer **MUST NOT**
/// listen on a routable interface by default, and the manifest that
/// advertises it is a file any process running as the user can write. A
/// dialler that honoured whatever `host` a manifest carried would stream
/// its selection gossip — and hand a full-duplex link into its own dispatch
/// stream — to any address one 200-byte JSON file named. So the connector
/// refuses everything outside CXP §10.5's loopback set, and refuses it
/// *before* opening a socket. See [cxpLoopbackDialAddress] for the set.
bool isCxpLoopbackHost(String host) => cxpLoopbackDialAddress(host) != null;

/// The address to dial for a manifest's [host], or null when [host] is
/// outside CXP §10.5's loopback set and must be refused.
///
/// The set is closed, and defined without asking any platform's address
/// parser — what a C library reads as loopback differs between platforms
/// (macOS reads `0127.0.0.1`, `127.000.000.001`, `::00001` and `::1%lo0` as
/// loopback), so a rule that deferred to one could not be reproduced by
/// another implementation or pinned by a test. After white space around the
/// value is ignored (Dart's `String.trim`), a host is in the set only if it
/// is:
///
/// - `localhost`, compared without regard to ASCII case — returned as
///   `localhost`, which the system resolver maps to loopback;
/// - an IPv4 address in `127.0.0.0/8` written as RFC 3986's `IPv4address`:
///   four dotted decimal octets, each 0–255, with no leading zeros; or
/// - `::1` in any form RFC 3986's `IPv6address` admits (`::1`,
///   `0:0:0:0:0:0:0:1`, `::0.0.0.1`, …), optionally in square brackets,
///   with no zone identifier.
///
/// Everything else is refused, IPv4-mapped addresses (`::ffff:127.0.0.1`)
/// and a bracketed IPv4 literal included. For a literal, the value
/// returned is the literal that was checked, unbracketed, so a dialler
/// connects to exactly what it checked (§10.5) and never hands a resolver
/// another spelling.
String? cxpLoopbackDialAddress(String host) {
  final trimmed = host.trim();
  if (_asciiLowerCase(trimmed) == 'localhost') return 'localhost';
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final literal = trimmed.substring(1, trimmed.length - 1);
    return _isIpv6Loopback(literal) ? literal : null;
  }
  final ipv4 = _parseIpv4(trimmed);
  if (ipv4 != null) return ipv4[0] == 127 ? trimmed : null;
  return _isIpv6Loopback(trimmed) ? trimmed : null;
}

/// [value] with `A`–`Z` lowered and every other code unit kept.
String _asciiLowerCase(String value) => String.fromCharCodes(
  value.codeUnits.map((c) => c >= 0x41 && c <= 0x5a ? c + 0x20 : c),
);

/// The four octets of an RFC 3986 `IPv4address`, or null when [value] is
/// not one: exactly four `dec-octet`s — `0`–`255`, ASCII digits, no
/// leading zero — separated by dots.
List<int>? _parseIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return null;
    if (!part.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) return null;
    if (part.length > 1 && part.codeUnitAt(0) == 0x30) return null;
    final octet = int.parse(part);
    if (octet > 255) return null;
    octets.add(octet);
  }
  return octets;
}

/// Whether [value] is an RFC 3986 `IPv6address` that names `::1`.
bool _isIpv6Loopback(String value) {
  final groups = _parseIpv6(value);
  if (groups == null) return false;
  for (var i = 0; i < 7; i++) {
    if (groups[i] != 0) return false;
  }
  return groups[7] == 1;
}

/// The eight 16-bit groups of an RFC 3986 `IPv6address`, or null when
/// [value] is not one.
///
/// The grammar, restated: `h16` groups of one to four hex digits separated
/// by `:`, at most one `::` standing for one or more zero groups, and an
/// `IPv4address` allowed as the last two groups' worth. Without `::` there
/// are exactly eight groups; with it, at most seven are written. No zone
/// identifier, no brackets, no white space.
List<int>? _parseIpv6(String value) {
  if (value.isEmpty) return null;
  final gap = value.indexOf('::');
  if (gap != value.lastIndexOf('::')) return null;
  if (gap < 0) {
    final groups = _ipv6Groups(value, mayEndInIpv4: true);
    return groups != null && groups.length == 8 ? groups : null;
  }
  final head = _ipv6Groups(value.substring(0, gap), mayEndInIpv4: false);
  final tail = _ipv6Groups(value.substring(gap + 2), mayEndInIpv4: true);
  if (head == null || tail == null) return null;
  final zeros = 8 - head.length - tail.length;
  if (zeros < 1) return null;
  return <int>[...head, for (var i = 0; i < zeros; i++) 0, ...tail];
}

/// The groups of one side of an `IPv6address` — [part] is `h16 *(":"
/// h16)`, or empty — or null when it is malformed.
List<int>? _ipv6Groups(String part, {required bool mayEndInIpv4}) {
  if (part.isEmpty) return <int>[];
  final fields = part.split(':');
  final groups = <int>[];
  for (var i = 0; i < fields.length; i++) {
    final field = fields[i];
    if (mayEndInIpv4 && i == fields.length - 1 && field.contains('.')) {
      final octets = _parseIpv4(field);
      if (octets == null) return null;
      groups
        ..add(octets[0] << 8 | octets[1])
        ..add(octets[2] << 8 | octets[3]);
      continue;
    }
    if (field.isEmpty || field.length > 4) return null;
    if (!field.codeUnits.every(_isHexDigit)) return null;
    groups.add(int.parse(field, radix: 16));
  }
  return groups;
}

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);

/// Thrown, and recorded as a [CxpDialFailure], when [CxpPeerConnector]
/// refuses to dial a discovered peer at all — as opposed to dialling it and
/// failing. Today the one reason is a manifest whose `host` is not loopback
/// (see [isCxpLoopbackHost]). No socket is opened for a refused dial and it
/// does not count in [CxpPeerConnector.dialAttempts].
@immutable
class CxpDialRefusedException implements Exception {
  /// Creates a refusal for the peer advertised at [host]:[port].
  const CxpDialRefusedException({
    required this.host,
    required this.port,
    required this.reason,
  });

  /// Host from the peer's manifest.
  final String host;

  /// Port from the peer's manifest.
  final int port;

  /// Why the dial was refused, written for a log or a diagnostics row.
  final String reason;

  @override
  String toString() => 'CxpDialRefusedException($host:$port: $reason)';
}

/// Why an outbound dial to a peer failed.
///
/// Connect failures used to be swallowed by a bare `on Object` with a
/// comment: a permanently unreachable peer was re-dialed every 5 s
/// forever with no diagnostic, no backoff and no signal to the product.
/// `CxpPeerConnector.dialFailures` surfaces them.
@immutable
class CxpDialFailure {
  /// Creates a dial-failure record.
  const CxpDialFailure({
    required this.peerId,
    required this.host,
    required this.port,
    required this.error,
    required this.consecutiveFailures,
    required this.nextRetryAfterTicks,
  });

  /// Peer whose manifest we were dialing.
  final String peerId;

  /// Host from the peer's manifest.
  final String host;

  /// Port from the peer's manifest.
  final int port;

  /// The error `connect` threw — typically a `SocketException`,
  /// `TimeoutException`, or `CxpHandshakeException`.
  final Object error;

  /// How many dials to this peer have failed in a row, including this
  /// one. Resets to zero on a successful handshake.
  final int consecutiveFailures;

  /// Retry-timer ticks that will be skipped before the next attempt —
  /// the backoff, expressed in [CxpPeerConnector.retryInterval] units.
  final int nextRetryAfterTicks;

  @override
  String toString() =>
      'CxpDialFailure($peerId @ $host:$port, '
      'attempt $consecutiveFailures, backoff ${nextRetryAfterTicks}t: '
      '$error)';
}

/// Dials every peer that [CxpDiscovery] surfaces and routes each link's
/// traffic into the local [CxpServer]'s dispatch stream.
///
/// Discovery alone only proves a manifest file exists — it establishes no
/// socket. Each product runs one connector alongside its server. The
/// connector watches the discovery stream and maintains one outbound
/// [LocalCxpClient] per non-self manifest:
///
/// - manifest added → connect (Hello handshake) to `host:port`;
/// - connect failure → retried every [retryInterval] while the manifest
///   remains known (covers "peer's server not yet listening" races and
///   peers that crashed without removing their manifest — those stop
///   being retried once discovery stale-prunes them);
/// - manifest removed → disconnect and dispose the client.
///
/// Connections are deliberately **symmetric**: when both peers run a
/// connector, each one dials the other, so each side's *server* sees an
/// inbound Hello and populates its `connectedPeers`.
///
/// ### Link traffic routing (the connector↔server seam)
///
/// An outbound link is a full-duplex CXP channel, and the remote peer
/// uses it as its *reply and delivery path back to us*: when the remote
/// product calls `sendTo(us, …)` or `broadcast(…)`, those frames arrive
/// on this connector's client socket — not on our server's accept loop.
/// A connector constructed with [server] therefore wires every link into
/// the server on handshake completion:
///
/// 1. **Inbound merge** — every frame the link's client receives is fed
///    into [CxpServer.injectInbound] tagged with the remote peer's
///    identity, so the product's single `server.inbound` subscription
///    sees link traffic and server-accepted traffic identically.
/// 2. **Reply route** — the link is registered via
///    [CxpServer.attachLinkedPeer], so `server.sendTo(peerId, …)` can
///    answer over the link (acks return on the channel the request
///    arrived on) even before/without the peer dialing us back.
/// 3. **Auto-subscribe** — the link's client sends a [Subscribe] for
///    [subscriptions] (default [cxpSubscribeToAll]) immediately after
///    the handshake, so the remote server's `broadcast` gossip
///    (`notify_selection`) reaches us without per-product wiring.
///    Products narrow or widen the filter set at runtime with
///    [updateSubscriptions].
///
/// Without [server], the connector degrades to presence-only dialing
/// (the remote server sees us connected, but link traffic is dropped).
class CxpPeerConnector {
  /// Creates a connector for [selfIdentity] fed by [discovery].
  ///
  /// Pass [server] to route link traffic into the local server's
  /// dispatch stream (see the class docs — production wiring should
  /// always do this). [subscriptions] seeds the auto-subscribe filter
  /// set sent on every link handshake; it defaults to
  /// [cxpSubscribeToAll].
  ///
  /// [clientFactory] is injectable for tests; production uses
  /// [LocalCxpClient].
  CxpPeerConnector({
    required this.selfIdentity,
    required this.discovery,
    this.server,
    List<CxpSubscription>? subscriptions,
    this.retryInterval = const Duration(seconds: 5),
    this.maxRetryBackoffTicks = 12,
    @visibleForTesting CxpClient Function(PeerIdentity self)? clientFactory,
  }) : _subscriptions = List.unmodifiable(subscriptions ?? cxpSubscribeToAll),
       _clientFactory =
           clientFactory ?? ((self) => LocalCxpClient(selfIdentity: self));

  /// Our own identity — manifests carrying this peerId are never dialed.
  final PeerIdentity selfIdentity;

  /// Discovery service whose peer set drives the connection set.
  final CxpDiscovery discovery;

  /// Local server that link traffic is routed into. When null, links
  /// provide presence only and their inbound frames are dropped.
  final CxpServer? server;

  /// How often failed / not-yet-attempted connections are retried.
  final Duration retryInterval;

  /// Ceiling on the exponential backoff, in [retryInterval] ticks.
  ///
  /// A peer whose dials keep failing is retried after 0, 1, 3, 7, …
  /// skipped ticks, capped here. At the 5 s default that settles at one
  /// attempt per minute instead of one every five seconds forever, while
  /// still recovering promptly once the peer comes up.
  final int maxRetryBackoffTicks;

  final CxpClient Function(PeerIdentity self) _clientFactory;

  final StreamController<CxpDialFailure> _dialFailures =
      StreamController<CxpDialFailure>.broadcast();

  /// Stream of outbound dial failures, one event per failed attempt.
  ///
  /// Products surface this (a status-bar hint, a diagnostics log) rather
  /// than leaving an unreachable peer indistinguishable from an absent
  /// one.
  Stream<CxpDialFailure> get dialFailures => _dialFailures.stream;

  /// The most recent failure per peer ID, for peers not currently
  /// connected. A peer disappears from this map when its handshake
  /// succeeds or its manifest is removed.
  Map<String, CxpDialFailure> get lastDialFailures =>
      Map.unmodifiable(_lastDialFailures);
  final Map<String, CxpDialFailure> _lastDialFailures =
      <String, CxpDialFailure>{};

  List<CxpSubscription> _subscriptions;

  final Map<String, _PeerLink> _links = <String, _PeerLink>{};
  StreamSubscription<CxpDiscoveryEvent>? _discoverySub;
  Timer? _retryTimer;
  var _running = false;

  /// Whether [start] has been called and [stop] has not.
  bool get isRunning => _running;

  /// Total outbound connection attempts made since construction,
  /// counting retries.
  ///
  /// Diagnostic counter: it observably increases while the retry loop is
  /// alive, so callers (and tests) can distinguish "still retrying" from
  /// "wedged" without timing assumptions. A dial the connector *refused*
  /// (see [CxpDialRefusedException]) opened no socket and is not counted.
  int get dialAttempts => _dialAttempts;
  var _dialAttempts = 0;

  /// The subscription filter set announced on every link.
  List<CxpSubscription> get subscriptions => _subscriptions;

  /// Identities of peers whose outbound handshake has completed.
  List<PeerIdentity> get connectedPeers => List.unmodifiable(<PeerIdentity>[
    for (final link in _links.values)
      if (link.client.isConnected && link.client.remotePeer != null)
        link.client.remotePeer!,
  ]);

  /// Replace the subscription filter set and re-announce it on every
  /// currently-connected link. Future links announce the new set on
  /// handshake.
  void updateSubscriptions(List<CxpSubscription> subscriptions) {
    _subscriptions = List.unmodifiable(subscriptions);
    for (final link in _links.values) {
      if (link.client.isConnected) {
        link.client.send(Subscribe(subscriptions: _subscriptions));
      }
    }
  }

  /// Start dialing: seeds from [CxpDiscovery.peers] (covering manifests
  /// discovered before the connector started) and follows the event
  /// stream thereafter.
  void start() {
    if (_running) return;
    _running = true;
    _discoverySub = discovery.events.listen(_onDiscoveryEvent);
    discovery.peers.forEach(_track);
    _retryTimer = Timer.periodic(retryInterval, (_) => _retryPending());
  }

  /// Stop dialing and tear down every outbound connection.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _discoverySub?.cancel();
    _discoverySub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final links = _links.values.toList(growable: false);
    _links.clear();
    _lastDialFailures.clear();
    for (final link in links) {
      await _disposeLink(link);
    }
  }

  /// Release the diagnostics stream. After [dispose] the connector cannot
  /// be restarted.
  Future<void> dispose() async {
    await stop();
    await _dialFailures.close();
  }

  void _onDiscoveryEvent(CxpDiscoveryEvent event) {
    if (!_running) return;
    if (event.added) {
      _track(event.manifest);
    } else {
      final link = _links.remove(event.manifest.identity.peerId);
      _lastDialFailures.remove(event.manifest.identity.peerId);
      if (link != null) unawaited(_disposeLink(link));
    }
  }

  void _track(CxpPeerManifest manifest) {
    final peerId = manifest.identity.peerId;
    if (peerId == selfIdentity.peerId) return; // never dial ourselves
    if (_links.containsKey(peerId)) return;
    final link = _PeerLink(
      manifest: manifest,
      client: _clientFactory(selfIdentity),
    );
    // Listen from creation, not from connect success: both are broadcast
    // streams, so events emitted before a listener attaches are lost.
    link
      ..inboundSub = link.client.inbound.listen(
        (message) => _onLinkInbound(link, message),
      )
      ..eventsSub = link.client.events.listen(
        (event) => _onLinkEvent(link, event),
      );
    _links[peerId] = link;
    unawaited(_connect(link));
  }

  void _onLinkInbound(_PeerLink link, CxpClientInbound inbound) {
    final sink = server;
    if (sink == null) return;
    final from = link.client.remotePeer;
    // Only handshake control frames precede remotePeer being set, and
    // the client consumes those internally; a null here means the link
    // is mid-teardown, where dropping is correct.
    if (from == null) return;
    sink.injectInbound(
      InboundCxpMessage(
        envelope: inbound.envelope,
        message: inbound.message,
        from: from,
      ),
    );
  }

  void _onLinkEvent(_PeerLink link, CxpConnectionEvent event) {
    if (event.connected) {
      final peer = event.peer;
      if (peer == null) return;
      link.attachedPeerId = peer.peerId;
      // Subscribe before anything else can happen on the link so no
      // broadcast window is missed.
      link.client.send(Subscribe(subscriptions: _subscriptions));
      server?.attachLinkedPeer(peer, link.client.send);
    } else {
      _detachLink(link);
    }
  }

  void _detachLink(_PeerLink link) {
    final attached = link.attachedPeerId;
    link.attachedPeerId = null;
    if (attached != null) server?.detachLinkedPeer(attached);
  }

  Future<void> _disposeLink(_PeerLink link) async {
    _detachLink(link);
    await link.dispose();
  }

  void _retryPending() {
    if (!_running) return;
    for (final link in _links.values) {
      if (link.client.isConnected || link.connecting) continue;
      // Exponential backoff: a permanently unreachable peer must not be
      // dialed at full rate forever.
      if (link.skipTicks > 0) {
        link.skipTicks--;
        continue;
      }
      unawaited(_connect(link));
    }
  }

  Future<void> _connect(_PeerLink link) async {
    if (link.connecting || link.client.isConnected) return;
    link.connecting = true;
    try {
      _refreshManifest(link);
      final host = link.manifest.host;
      final address = cxpLoopbackDialAddress(host);
      if (address == null) {
        // Refused, not attempted: no socket is opened towards an address a
        // manifest file chose. Thrown into the same bookkeeping as a failed
        // dial so the product's unreachable-peer row shows the reason and
        // the retry backs off like any other failure; the check re-runs on
        // each retry and costs no I/O.
        throw CxpDialRefusedException(
          host: host,
          port: link.manifest.port,
          reason:
              'manifest advertises a non-loopback host; CXP peers are '
              'same-machine only',
        );
      }
      _dialAttempts++;
      // The manifest is where the peer's token lives; presenting it is
      // what a 1.2 receiver requires, and a pre-1.2 manifest carries none.
      // The address is the literal that was checked, trimmed and
      // unbracketed, never the manifest's own spelling (§10.5).
      await link.client.connect(
        host: address,
        port: link.manifest.port,
        token: link.manifest.token,
      );
      // Handshake succeeded — clear the backoff and the recorded failure.
      link
        ..consecutiveFailures = 0
        ..skipTicks = 0;
      _lastDialFailures.remove(link.manifest.identity.peerId);
    } on Object catch (error) {
      // Peer not listening (yet, or anymore), or the handshake failed or
      // timed out. The retry timer tries again — with backoff — while the
      // manifest is known; discovery stale-prunes dead peers. Unlike
      // before, the failure is observable rather than silently dropped.
      link.consecutiveFailures++;
      final backoff = _backoffTicksFor(link.consecutiveFailures);
      link.skipTicks = backoff;
      final failure = CxpDialFailure(
        peerId: link.manifest.identity.peerId,
        host: link.manifest.host,
        port: link.manifest.port,
        error: error,
        consecutiveFailures: link.consecutiveFailures,
        nextRetryAfterTicks: backoff,
      );
      _lastDialFailures[failure.peerId] = failure;
      if (!_dialFailures.isClosed) _dialFailures.add(failure);
    } finally {
      link.connecting = false;
    }
  }

  /// Replaces [link]'s manifest with the one discovery read most recently
  /// for the same peer, before each dial.
  ///
  /// Discovery reports only additions and removals, so a manifest rewritten
  /// under the same `peer_id` — a server restarted on another port, or with
  /// another token — is not an event, and a link kept the first manifest it
  /// was given. §7.4: a token belongs to one manifest, and a dialler finds
  /// the current one by reading the manifest again. Every Crux product
  /// mints a new peer id whenever it starts its server, so this changes
  /// nothing for them; it matters to a host that keeps its id across a
  /// restart.
  void _refreshManifest(_PeerLink link) {
    final peerId = link.manifest.identity.peerId;
    for (final manifest in discovery.peers) {
      if (manifest.identity.peerId == peerId) {
        link.manifest = manifest;
        return;
      }
    }
  }

  /// 0, 1, 3, 7, 15, … ticks, capped at [maxRetryBackoffTicks].
  int _backoffTicksFor(int consecutiveFailures) {
    if (consecutiveFailures <= 1) return 0;
    final exponent = consecutiveFailures - 1;
    if (exponent >= 31) return maxRetryBackoffTicks;
    final ticks = (1 << exponent) - 1;
    return ticks < maxRetryBackoffTicks ? ticks : maxRetryBackoffTicks;
  }
}

class _PeerLink {
  _PeerLink({required this.manifest, required this.client});

  /// The peer's manifest as last read — refreshed before every dial.
  CxpPeerManifest manifest;
  final CxpClient client;
  bool connecting = false;

  /// Dials to this peer that have failed in a row. Drives the backoff.
  int consecutiveFailures = 0;

  /// Retry-timer ticks still to be skipped before the next dial.
  int skipTicks = 0;

  /// Peer ID currently registered with the server via `attachLinkedPeer`,
  /// or null when not attached. Retained past the client's own teardown
  /// so the detach can name the peer after `remotePeer` is cleared.
  String? attachedPeerId;

  StreamSubscription<CxpClientInbound>? inboundSub;
  StreamSubscription<CxpConnectionEvent>? eventsSub;

  Future<void> dispose() async {
    await inboundSub?.cancel();
    inboundSub = null;
    await eventsSub?.cancel();
    eventsSub = null;
    final c = client;
    if (c is LocalCxpClient) {
      await c.dispose();
    } else {
      await c.disconnect();
    }
  }
}
