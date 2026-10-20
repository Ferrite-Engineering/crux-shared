// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show pid;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_product_binding.dart';

/// How long a directed send waits for the peer's acknowledgement.
const Duration kCxpAckTimeout = Duration(seconds: 5);

/// The outcome of a directed `request_highlight`.
typedef CxpHighlightDelivery = ({bool delivered, RequestHighlightAck? ack});

/// One product's running CXP presence: the server, its discovery manifest,
/// the discovery watcher and the connector that dials every peer.
///
/// The shared form of the four products' own server wrappers. It owns the
/// whole lifecycle, routes what peers send to the product's
/// [CxpRequestHandler] and acknowledges it, and reports everything that
/// happens as [CrossProbeEvent]s and peer snapshots for the panel, the
/// toolbar badge and the cross-probe menus.
///
/// Start and stop are safe to interleave: a [stop] that lands while [start]
/// is still binding unwinds the start rather than leaving a listener and a
/// dialling connector nothing will close. Neither throws: a bind failure or
/// an unwritable manifest directory leaves the runtime not available, with
/// [unavailableReason] saying why.
class CxpRuntime {
  /// Creates a runtime for [binding]. Nothing runs until [start].
  ///
  /// `handler` is called at each request, so a product can swap the handler a
  /// provider gives without restarting the server. The factories exist for
  /// tests.
  CxpRuntime({
    required this.binding,
    required this.productVersion,
    required this.manifestDirectory,
    required this.port,
    required this._handler,
    this._onAttention,
    this._attentionEnabled,
    this._serverFactory,
    CxpManifestWriter Function(String directory)? manifestWriterFactory,
    CxpDiscovery Function(String directory, String selfPeerId)?
    discoveryFactory,
    int? processId,
    DateTime Function()? clock,
  }) : _manifestWriterFactory =
           manifestWriterFactory ??
           ((dir) => CxpManifestWriter(manifestDirectory: dir)),
       _discoveryFactory =
           discoveryFactory ??
           ((dir, self) =>
               CxpDiscovery(manifestDirectory: dir, selfPeerId: self)),
       _processId = processId ?? pid,
       _clock = clock ?? DateTime.now;

  /// What is this product's own.
  final CxpProductBinding binding;

  /// The version this build reports to peers.
  final String productVersion;

  /// The suite-shared discovery directory.
  final String manifestDirectory;

  /// The requested listening port.
  final int port;

  final CxpRequestHandler Function() _handler;
  final void Function()? _onAttention;
  final bool Function()? _attentionEnabled;
  final LocalCxpServer Function(PeerIdentity self)? _serverFactory;
  final CxpManifestWriter Function(String directory) _manifestWriterFactory;
  final CxpDiscovery Function(String directory, String selfPeerId)
  _discoveryFactory;
  final int _processId;
  final DateTime Function() _clock;

  /// This process's identity: peer id `<product>-<pid>-<started ms>`, so two
  /// processes of one product on a machine stay distinct.
  late final PeerIdentity selfIdentity = PeerIdentity(
    peerId:
        '${binding.productName}-$_processId-'
        '${_clock().millisecondsSinceEpoch}',
    productName: binding.productName,
    productVersion: productVersion,
    capabilities: binding.advertisedCapabilities,
  );

  LocalCxpServer? _server;
  CxpManifestWriter? _manifestWriter;
  CxpDiscovery? _discovery;
  CxpPeerConnector? _connector;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _running = false;
  bool _stopped = false;
  String? _unavailableReason;

  final StreamController<CrossProbeEvent> _events =
      StreamController<CrossProbeEvent>.broadcast();
  final StreamController<List<PeerIdentity>> _peerChanges =
      StreamController<List<PeerIdentity>>.broadcast();
  final StreamController<List<CxpDialFailure>> _unreachableChanges =
      StreamController<List<CxpDialFailure>>.broadcast();

  /// Whether the server is bound and accepting peers.
  bool get isAvailable => _running && _server?.boundPort != null;

  /// The bound port, or null when not available.
  int? get boundPort => _running ? _server?.boundPort : null;

  /// Why the runtime is not available, or degraded; null when it came up
  /// cleanly or has not started.
  String? get unavailableReason => _unavailableReason;

  /// Everything that happens, for the panel's event log: peers connecting
  /// and leaving, and every message sent or received.
  Stream<CrossProbeEvent> get events => _events.stream;

  /// A fresh [peers] snapshot whenever it may have changed.
  Stream<List<PeerIdentity>> get peerChanges => _peerChanges.stream;

  /// A fresh [unreachablePeers] snapshot whenever it may have changed.
  Stream<List<CxpDialFailure>> get unreachableChanges =>
      _unreachableChanges.stream;

  /// The connected peers, one entry per peer id, never this process.
  List<PeerIdentity> get peers {
    if (!_running) return const <PeerIdentity>[];
    final byId = <String, PeerIdentity>{};
    for (final peer in <PeerIdentity>[
      ...?_server?.connectedPeers,
      ...?_connector?.connectedPeers,
    ]) {
      if (peer.peerId == selfIdentity.peerId) continue;
      byId.putIfAbsent(peer.peerId, () => peer);
    }
    return List<PeerIdentity>.unmodifiable(byId.values);
  }

  /// Peers that were discovered but could not be dialled. Empty when the
  /// runtime is not running; a peer leaves once it connects or its manifest
  /// goes away.
  List<CxpDialFailure> get unreachablePeers => _running
      ? List<CxpDialFailure>.unmodifiable(
          _connector?.lastDialFailures.values ?? const <CxpDialFailure>[],
        )
      : const <CxpDialFailure>[];

  /// Starts the server, writes the manifest, and starts discovery and the
  /// connector. Idempotent; a no-op after [stop].
  Future<void> start() async {
    if (_running || _stopped) return;
    _unavailableReason = null;
    final server =
        _serverFactory?.call(selfIdentity) ??
        LocalCxpServer(
          selfIdentity: selfIdentity,
          port: port,
          nameResolver: binding.nameResolver,
          containment: binding.containment,
        );
    _server = server;
    try {
      await server.start();
    } on Object catch (e) {
      await _abortStart('CXP cross-probe unavailable (bind failed): $e');
      return;
    }
    if (_stopped) {
      await server.stop();
      _server = null;
      return;
    }
    final bound = server.boundPort;
    if (bound == null) {
      await _abortStart('CXP cross-probe unavailable: the server did not bind');
      return;
    }
    _running = true;
    _subscriptions
      ..add(server.inbound.listen(_onInbound))
      ..add(server.presence.listen(_onPresence));
    try {
      final writer = _manifestWriterFactory(manifestDirectory);
      _manifestWriter = writer;
      await writer.write(
        identity: selfIdentity,
        host: '127.0.0.1',
        port: bound,
      );
      final discovery = _discoveryFactory(
        manifestDirectory,
        selfIdentity.peerId,
      );
      _discovery = discovery;
      _subscriptions.add(discovery.events.listen((_) => _publishPeers()));
      await discovery.start();
      // `server:` routes every dialled link's frames into this server, so a
      // peer this process only dialled still reaches the request handlers
      // and receives broadcasts.
      final connector = CxpPeerConnector(
        selfIdentity: selfIdentity,
        discovery: discovery,
        server: server,
      );
      _connector = connector;
      // Subscribed before start(), so the first dial's failure is not lost.
      _subscriptions.add(
        connector.dialFailures.listen((_) => _publishUnreachable()),
      );
      connector.start();
    } on Object catch (e) {
      _unavailableReason = 'CXP peer discovery degraded: $e';
    }
    if (_stopped) {
      await stop();
      return;
    }
    _publishPeers();
  }

  Future<void> _abortStart(String reason) async {
    _unavailableReason = reason;
    try {
      await _server?.stop();
    } on Object {
      // The server never bound; nothing to release.
    }
    _server = null;
    _running = false;
  }

  /// Says goodbye to every peer, removes the manifest and stops everything.
  /// Not gated on a finished [start], so it also unwinds one in flight.
  /// Idempotent. Afterwards [peers] and [unreachablePeers] are empty.
  Future<void> stop() async {
    _stopped = true;
    final wasRunning = _running;
    _running = false;
    final subscriptions = List<StreamSubscription<Object?>>.of(_subscriptions);
    _subscriptions.clear();
    final connector = _connector;
    _connector = null;
    final discovery = _discovery;
    _discovery = null;
    final writer = _manifestWriter;
    _manifestWriter = null;
    final server = _server;
    _server = null;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    if (server != null && wasRunning) {
      try {
        server.broadcast(const Goodbye(reason: 'server_stopping'));
      } on Object {
        // Best effort.
      }
    }
    await connector?.stop();
    await discovery?.stop();
    try {
      await writer?.remove();
    } on Object {
      // A manifest that cannot be removed is reaped by its peers.
    }
    await server?.stop();
    if (!_peerChanges.isClosed) _peerChanges.add(const <PeerIdentity>[]);
    if (!_unreachableChanges.isClosed) {
      _unreachableChanges.add(const <CxpDialFailure>[]);
    }
  }

  /// Stops and releases the event streams. The runtime cannot be restarted;
  /// a settings change creates a new one.
  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _peerChanges.close();
    await _unreachableChanges.close();
  }

  /// Announces [message] to every subscribed peer. A no-op when not
  /// running.
  void broadcast(CxpMessage message, {String? summary}) {
    final server = _server;
    if (!_running || server == null) return;
    server.broadcast(message);
    _emit(
      CrossProbeEvent(
        kind: _outboundKind(message),
        direction: CrossProbeEventDirection.outbound,
        peerLabel: '(broadcast)',
        timestamp: _clock(),
        summary: summary ?? _summarize(message),
        messageKind: message.kind,
      ),
    );
  }

  /// Sends [message] to the peer [peerId]; false when that peer is not
  /// connected or the runtime is not running.
  bool sendTo(String peerId, CxpMessage message, {String? summary}) {
    final server = _server;
    if (!_running || server == null) return false;
    final delivered = server.sendTo(peerId, message);
    if (delivered) {
      _emit(
        CrossProbeEvent(
          kind: _outboundKind(message),
          direction: CrossProbeEventDirection.outbound,
          peerLabel: _labelOf(peerId),
          timestamp: _clock(),
          summary: summary ?? _summarize(message),
          messageKind: message.kind,
        ),
      );
    }
    return delivered;
  }

  /// Sends [request] to [peerId] and waits up to [timeout] for its
  /// acknowledgement. `delivered` is false when the peer was not reachable;
  /// `ack` is null when no acknowledgement came back in time.
  Future<CxpHighlightDelivery> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = kCxpAckTimeout,
    String? summary,
  }) async {
    final server = _server;
    if (!_running || server == null) return (delivered: false, ack: null);
    final completer = Completer<RequestHighlightAck>();
    // The next acknowledgement from this peer answers this request: an ack
    // is only ever a reply to a directed request_highlight, and directed
    // sends are its only source.
    final sub = server.inbound.listen((inbound) {
      final message = inbound.message;
      if (inbound.from.peerId == peerId &&
          message is RequestHighlightAck &&
          !completer.isCompleted) {
        completer.complete(message);
      }
    });
    if (!sendTo(peerId, request, summary: summary)) {
      await sub.cancel();
      return (delivered: false, ack: null);
    }
    RequestHighlightAck? ack;
    try {
      ack = await completer.future.timeout(timeout);
    } on TimeoutException {
      ack = null;
    } finally {
      await sub.cancel();
    }
    return (delivered: true, ack: ack);
  }

  void _publishPeers() {
    if (!_peerChanges.isClosed) _peerChanges.add(peers);
    _publishUnreachable();
  }

  void _publishUnreachable() {
    if (!_unreachableChanges.isClosed) {
      _unreachableChanges.add(unreachablePeers);
    }
  }

  void _emit(CrossProbeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _labelOf(String peerId) {
    for (final peer in peers) {
      if (peer.peerId == peerId) return cxpProductDisplayName(peer.productName);
    }
    return peerId;
  }

  void _onPresence(PeerPresenceEvent event) {
    final label = cxpProductDisplayName(event.peer.productName);
    _emit(
      event.connected
          ? CrossProbeEvent.peerConnected(peerLabel: label, timestamp: _clock())
          : CrossProbeEvent.peerDisconnected(
              peerLabel: label,
              timestamp: _clock(),
            ),
    );
    _publishPeers();
  }

  Future<void> _onInbound(InboundCxpMessage inbound) async {
    final message = inbound.message;
    // Acknowledgements are replies, not traffic worth a row of their own.
    if (message is RequestHighlightAck ||
        message is RequestOpenSourceAck ||
        message is RequestOpenArtifactAck) {
      return;
    }
    _emit(
      CrossProbeEvent(
        kind: _inboundKind(message),
        direction: CrossProbeEventDirection.inbound,
        peerLabel: inbound.from.productName.isEmpty
            ? inbound.from.peerId
            : cxpProductDisplayName(inbound.from.productName),
        timestamp: _clock(),
        summary: _summarize(message),
        messageKind: message.kind,
      ),
    );
    final handler = _handler();
    final from = inbound.from;
    final replyTo = inbound.envelope.messageId;
    switch (message) {
      case final RequestHighlight request:
        final result = await _invoke(() => handler.highlight(request, from));
        _reply(
          from.peerId,
          RequestHighlightAck(
            inReplyTo: replyTo,
            honored: result.honored,
            reason: result.reason,
          ),
        );
        if (result.honored) _attention();
      case final RequestOpenSource request:
        final result = await _invoke(() => handler.openSource(request, from));
        _reply(
          from.peerId,
          RequestOpenSourceAck(
            inReplyTo: replyTo,
            honored: result.honored,
            reason: result.reason,
          ),
        );
        if (result.honored) _attention();
      case final RequestOpenArtifact request:
        final result = await _invoke(() => handler.openArtifact(request, from));
        _reply(
          from.peerId,
          RequestOpenArtifactAck(
            inReplyTo: replyTo,
            honored: result.honored,
            reason: result.reason,
          ),
        );
        if (result.honored) _attention();
      case final NotifySelection selection:
        try {
          handler.selection(selection, from);
        } on Object {
          // A selection has no reply; a failing handler only loses it.
        }
      default:
        break;
    }
  }

  void _reply(String peerId, CxpMessage message) {
    final server = _server;
    if (!_running || server == null) return;
    server.sendTo(peerId, message);
  }

  void _attention() {
    final enabled = _attentionEnabled?.call() ?? true;
    if (!enabled) return;
    try {
      _onAttention?.call();
    } on Object {
      // Attention is a courtesy; failing to ask for it changes nothing.
    }
  }

  static Future<CxpHandlerResult> _invoke(
    Future<CxpHandlerResult> Function() body,
  ) async {
    try {
      return await body();
    } on Object catch (e) {
      return CxpHandlerResult(honored: false, reason: '$e');
    }
  }

  static CrossProbeEventKind _outboundKind(CxpMessage message) =>
      switch (message) {
        NotifySelection() => CrossProbeEventKind.selectionSent,
        RequestHighlight() => CrossProbeEventKind.highlightSent,
        RequestOpenArtifact() => CrossProbeEventKind.openArtifact,
        _ => CrossProbeEventKind.other,
      };

  static CrossProbeEventKind _inboundKind(CxpMessage message) =>
      switch (message) {
        NotifySelection() => CrossProbeEventKind.selectionReceived,
        RequestHighlight() => CrossProbeEventKind.highlightReceived,
        RequestOpenArtifact() => CrossProbeEventKind.openArtifact,
        _ => CrossProbeEventKind.other,
      };

  static String? _summarize(CxpMessage message) => switch (message) {
    NotifySelection(:final elements, :final displayName)
        when elements.isNotEmpty =>
      displayName ?? elements.first.path,
    RequestHighlight(:final element) => element.path,
    RequestOpenSource(:final filePath, :final line) => '$filePath:$line',
    RequestOpenArtifact(:final designId, :final artifactKind) =>
      '$designId, $artifactKind',
    _ => null,
  };
}

/// The suite's display name for a wire product name: `wavecrux` is
/// WaveCrux. A product outside the suite shows its own name with the first
/// letter capitalized.
String cxpProductDisplayName(String productName) {
  switch (productName.toLowerCase()) {
    case 'wavecrux':
      return 'WaveCrux';
    case 'netcrux':
      return 'NetCrux';
    case 'lintcrux':
      return 'LintCrux';
    case 'simcrux':
      return 'SimCrux';
  }
  if (productName.isEmpty) return productName;
  return productName[0].toUpperCase() + productName.substring(1);
}
