// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:edacrux_cxp/src/cxp_client.dart';
import 'package:edacrux_cxp/src/cxp_discovery.dart';
import 'package:edacrux_cxp/src/cxp_link_sink.dart';
import 'package:edacrux_cxp/src/cxp_manifest_directory.dart';
import 'package:edacrux_cxp/src/cxp_peer_connector.dart';
import 'package:edacrux_cxp/src/element_id.dart';
import 'package:edacrux_cxp/src/messages/cxp_message.dart';
import 'package:edacrux_cxp/src/messages/error_response.dart';
import 'package:edacrux_cxp/src/messages/highlight.dart';
import 'package:edacrux_cxp/src/messages/open_artifact.dart';
import 'package:edacrux_cxp/src/messages/open_source.dart';
import 'package:edacrux_cxp/src/messages/selection.dart';
import 'package:edacrux_cxp/src/messages/subscribe.dart';
import 'package:edacrux_cxp/src/peer_identity.dart';
import 'package:edacrux_cxp/src/probe/cxp_probe_types.dart';
import 'package:edacrux_cxp/src/stream_coordinate.dart';

/// The `metadata` key [CxpProbe] puts a simulation or waveform time under
/// when a send method is given `timePs`: picoseconds, as an integer.
///
/// This is **not** a key CXP registers (§9.3.1 lists the registered ones),
/// and no app acts on it yet; the specification's own `notify_selection`
/// example uses the same name. A receiver must ignore a metadata key it does
/// not understand, so sending it is safe, and an app that adopts it later
/// starts honouring it without a change here.
const String cxpTimePsMetadataKey = 'time_ps';

/// The default subscription of a [CxpProbe]: every `notify_selection`.
const List<CxpSubscription> cxpProbeDefaultSubscriptions = <CxpSubscription>[
  CxpSubscription(messageKind: CxpMessageKind.notifySelection),
];

/// A program that takes part in CXP cross-probing by dialling the peers
/// already running: it finds them, connects, and sends them typed requests
/// ("show this signal", "highlight this net", "open this scope", "open this
/// source line") and hears what they select.
///
/// A probe is a *dial-only* peer. It publishes no manifest and listens on no
/// port, so it needs no setup beyond one call and it opens no socket a
/// stranger could dial; the cost is that no peer discovers it, and the only
/// traffic it sees is what travels on the links it opened. Those links are
/// full-duplex (CXP §3): a peer answers requests on them, broadcasts its
/// selection to a subscribed probe on them, and may send the probe a request
/// of its own, which a [CxpProbeRequestHandler] answers.
///
/// ```dart
/// final probe = await CxpProbe.start(name: 'my-simulator');
/// await probe.waitForPeer(product: 'wavecrux');
/// final replies = await probe.showSignal('top.cpu.alu.result', timePs: 41250);
/// print(replies);
/// await probe.close();
/// ```
///
/// Everything here runs on one isolate and is not thread safe across
/// isolates; make one probe per isolate.
class CxpProbe {
  CxpProbe._({
    required this.identity,
    required this.ackTimeout,
    required CxpDiscovery discovery,
    required this._handler,
    required List<CxpSubscription> subscriptions,
    required Duration retryInterval,
  }) : _discovery = discovery {
    _sink = _ProbeSink(this);
    _connector = CxpPeerConnector(
      selfIdentity: identity,
      discovery: discovery,
      server: _sink,
      subscriptions: subscriptions,
      retryInterval: retryInterval,
      clientFactory: _makeClient,
    );
  }

  /// Starts a probe: scans the manifest directory for running peers and dials
  /// each one it finds, now and as new ones start.
  ///
  /// [name] is the product name this program announces (shown in a peer's
  /// connected-peers list); it is lower-cased into the probe's `peerId`, so
  /// keep it short and made of letters, digits, `-` and `_`. [version] is the
  /// product version announced alongside it.
  ///
  /// [manifestDirectory] is the directory peers publish into; the default is
  /// `sharedCxpManifestDirectory()`, which every Crux app uses. Pass another
  /// to probe a private set of peers, as a test does.
  ///
  /// [subscriptions] says which broadcasts the peers should send this probe
  /// ([cxpProbeDefaultSubscriptions]: every selection). Pass an empty list to
  /// hear nothing but answers to requests.
  ///
  /// [ackTimeout] bounds how long a send method waits for each peer's
  /// acknowledgement. [scanInterval] is how often the directory is rescanned
  /// and [retryInterval] how often a link that failed is retried.
  ///
  /// [handler] answers requests that peers send the probe; without one every
  /// such request is declined with a reason.
  ///
  /// Throws [StateError] when the manifest directory cannot be resolved (no
  /// home directory, or a web build): see `sharedCxpManifestDirectory`.
  static Future<CxpProbe> start({
    required String name,
    String version = '0.0.0',
    Set<String> capabilities = const <String>{},
    String? activeDocument,
    String? manifestDirectory,
    List<CxpSubscription> subscriptions = cxpProbeDefaultSubscriptions,
    Duration ackTimeout = const Duration(seconds: 5),
    Duration scanInterval = const Duration(seconds: 1),
    Duration retryInterval = const Duration(seconds: 2),
    CxpProbeRequestHandler? handler,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final directory = manifestDirectory ?? sharedCxpManifestDirectory();
    final identity = PeerIdentity(
      peerId: _newPeerId(name),
      productName: name,
      productVersion: version,
      capabilities: capabilities,
      activeDocument: PeerIdentity.normalizeActiveDocument(activeDocument),
    );
    final discovery = CxpDiscovery(
      manifestDirectory: directory,
      selfPeerId: identity.peerId,
      scanInterval: scanInterval,
    );
    final probe = CxpProbe._(
      identity: identity,
      ackTimeout: ackTimeout,
      discovery: discovery,
      handler: handler,
      subscriptions: subscriptions,
      retryInterval: retryInterval,
    );
    await discovery.start();
    probe._connector.start();
    return probe;
  }

  /// The identity this program announces to peers.
  final PeerIdentity identity;

  /// How long a send method waits for each peer's acknowledgement.
  final Duration ackTimeout;

  final CxpDiscovery _discovery;
  final CxpProbeRequestHandler? _handler;
  late final _ProbeSink _sink;
  late final CxpPeerConnector _connector;
  final List<LocalCxpClient> _clients = <LocalCxpClient>[];
  final Map<String, _Link> _links = <String, _Link>{};
  final Map<String, Completer<CxpProbeReply>> _waiters =
      <String, Completer<CxpProbeReply>>{};
  final StreamController<CxpProbeEvent> _events =
      StreamController<CxpProbeEvent>.broadcast();
  var _closed = false;

  CxpClient _makeClient(PeerIdentity self) {
    final client = LocalCxpClient(selfIdentity: self);
    _clients.add(client);
    return client;
  }

  /// Everything the probe reports: peers joining and leaving, selections
  /// peers announce, and requests peers send. A broadcast stream; subscribe
  /// before the events you want can happen.
  Stream<CxpProbeEvent> get events => _events.stream;

  /// The peers whose handshake has completed, oldest first.
  List<CxpProbePeer> get peers => List<CxpProbePeer>.unmodifiable(
    <CxpProbePeer>[for (final link in _links.values) link.peer],
  );

  /// Why dialling a discovered peer failed, one event per failed attempt: an
  /// unreachable port, a refused handshake (`CxpHandshakeException`, such as
  /// `unauthorized`), a manifest naming a non-loopback host
  /// (`CxpDialRefusedException`). The probe keeps retrying with backoff.
  Stream<CxpDialFailure> get dialFailures => _connector.dialFailures;

  /// The first connected peer, optionally of one [product] (case
  /// insensitive), waiting up to [timeout] for one to connect.
  ///
  /// Throws [TimeoutException] when none does: no such app is running, or
  /// its CXP is turned off, or it refused the handshake (see
  /// [dialFailures]).
  Future<CxpProbePeer> waitForPeer({
    String? product,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    CxpProbePeer? find() {
      for (final peer in peers) {
        if (product == null || peer.isProduct(product)) return peer;
      }
      return null;
    }

    final now = find();
    if (now != null) return now;
    final found = Completer<CxpProbePeer>();
    final sub = events.listen((event) {
      if (event is CxpPeerJoined &&
          (product == null || event.peer.isProduct(product)) &&
          !found.isCompleted) {
        found.complete(event.peer);
      }
    });
    try {
      // A peer may have joined between the first look and the listen.
      final late = find();
      if (late != null) return late;
      return await found.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'No ${product ?? 'CXP'} peer connected',
          timeout,
        ),
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Asks the peers to bring the signal at [path] into view (`signal`, CXP
  /// §8.2: for example `top.cpu.alu.result[7:0]`), at simulation time
  /// [timePs] picoseconds when given.
  ///
  /// Goes to every connected peer that accepts `signal`, or only to [to] or
  /// to the peers of [product]. [designId] is the opaque design identifier
  /// (§9.10.1) that lets a peer find the design when it has not got it open.
  /// [metadata] is extra free-form context, sent as given.
  ///
  /// [timePs] travels under [cxpTimePsMetadataKey], which no app honours
  /// yet; see there.
  Future<List<CxpProbeReply>> showSignal(
    String path, {
    int? timePs,
    String? designId,
    Map<String, Object?> metadata = const <String, Object?>{},
    CxpProbePeer? to,
    String? product,
  }) => highlight(
    ElementKind.signal,
    path,
    timePs: timePs,
    designId: designId,
    metadata: metadata,
    to: to,
    product: product,
  );

  /// Asks the peers to highlight the net at [path] (`net`). See
  /// [showSignal] for the targeting and the other parameters.
  Future<List<CxpProbeReply>> highlightNet(
    String path, {
    int? timePs,
    String? designId,
    Map<String, Object?> metadata = const <String, Object?>{},
    CxpProbePeer? to,
    String? product,
  }) => highlight(
    ElementKind.net,
    path,
    timePs: timePs,
    designId: designId,
    metadata: metadata,
    to: to,
    product: product,
  );

  /// Asks the peers to highlight the cell at [path] (`cell`, a cell of a
  /// post-synthesis or post-place netlist, `<top>.<flat cell name>`). See
  /// [showSignal] for the targeting and the other parameters.
  Future<List<CxpProbeReply>> highlightCell(
    String path, {
    String? designId,
    Map<String, Object?> metadata = const <String, Object?>{},
    CxpProbePeer? to,
    String? product,
  }) => highlight(
    ElementKind.cell,
    path,
    designId: designId,
    metadata: metadata,
    to: to,
    product: product,
  );

  /// Asks the peers to open the hierarchical scope at [path] (`scope`: a
  /// module, instance or generate block). See [showSignal] for the targeting
  /// and the other parameters.
  Future<List<CxpProbeReply>> openScope(
    String path, {
    String? designId,
    Map<String, Object?> metadata = const <String, Object?>{},
    CxpProbePeer? to,
    String? product,
  }) => highlight(
    ElementKind.scope,
    path,
    designId: designId,
    metadata: metadata,
    to: to,
    product: product,
  );

  /// Asks the peers to bring the element of [kind] at [path] into view
  /// (`request_highlight`, CXP §9.4), and returns each peer's answer.
  ///
  /// The other methods of this family are this with the kind fixed. Use it
  /// for a kind they do not name (`instance`, `port`, `marker`, `property`,
  /// or one the specification adds later; [ElementKind] is open).
  ///
  /// Without [to], the request goes to each connected peer, narrowed to
  /// [product] when given, **that accepts [kind]** under the
  /// `cxp.accepts:<kind>` convention (CXP §8.1; see
  /// [CxpProbePeer.accepts]); a peer that does not is skipped, so a kind
  /// nobody accepts returns an empty list, not an error. With [to] the
  /// request is sent to that peer whatever it advertises. [coordinate]
  /// says where within the element to land (§9.9).
  Future<List<CxpProbeReply>> highlight(
    ElementKind kind,
    String path, {
    int? timePs,
    String? designId,
    Map<String, Object?> metadata = const <String, Object?>{},
    CxpStreamCoordinate? coordinate,
    CxpProbePeer? to,
    String? product,
  }) {
    final request = RequestHighlight(
      element: ElementId(kind: kind, path: path),
      coordinate: coordinate,
      metadata: _metadataWith(metadata, timePs: timePs, designId: designId),
    );
    return _ask(
      _targets(to: to, product: product, accepting: kind),
      request,
      to: to,
    );
  }

  /// Asks the peers to open the source file at [filePath] on [line] (and
  /// [column]), 1-based (`request_open_source`, CXP §9.6).
  ///
  /// [filePath] is an absolute path both programs can see; a peer refuses a
  /// path outside the directories its user has opened (§11.3) and says so in
  /// the reply. Goes to every connected peer, or only to [to] or the peers of
  /// [product].
  Future<List<CxpProbeReply>> openSource(
    String filePath,
    int line, {
    int? column,
    CxpProbePeer? to,
    String? product,
  }) {
    if (line < 1) {
      throw ArgumentError.value(line, 'line', 'lines are 1-based');
    }
    if (column != null && column < 1) {
      throw ArgumentError.value(column, 'column', 'columns are 1-based');
    }
    return _ask(
      _targets(to: to, product: product),
      RequestOpenSource(filePath: filePath, line: line, column: column),
      to: to,
    );
  }

  /// Tells the peers what this program has selected (`notify_selection`,
  /// CXP §9.3): a statement, which a peer may act on by highlighting the
  /// same elements, and which is not acknowledged. Resolves once the message
  /// is on each link, with the peers it was sent to.
  ///
  /// An empty [elements] list retracts the selection (§9.1.2); see
  /// [clearSelection].
  Future<List<CxpProbePeer>> select(
    List<ElementId> elements, {
    String? displayName,
    String? designId,
    Map<String, Object?> metadata = const <String, Object?>{},
    CxpProbePeer? to,
    String? product,
  }) async {
    final message = NotifySelection(
      elements: List<ElementId>.unmodifiable(elements),
      displayName: displayName,
      metadata: _metadataWith(metadata, designId: designId),
    );
    final sent = <CxpProbePeer>[];
    for (final link in _targets(to: to, product: product)) {
      if (link.client.sendTracked(message) != null) sent.add(link.peer);
    }
    return sent;
  }

  /// Tells the peers this program's selection is now empty (a retraction,
  /// CXP §9.1.2). See [select].
  Future<List<CxpProbePeer>> clearSelection({
    CxpProbePeer? to,
    String? product,
  }) => select(const <ElementId>[], to: to, product: product);

  /// Closes every link, saying goodbye to each peer, and stops scanning.
  /// Pending sends complete as [CxpProbeOutcome.failed]. Safe to call twice.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connector.dispose();
    await _discovery.stop();
    for (final waiter in _waiters.values.toList()) {
      if (!waiter.isCompleted) {
        waiter.completeError(const _LinkClosed('the probe was closed'));
      }
    }
    _waiters.clear();
    _links.clear();
    await _events.close();
  }

  // -------------------------------------------------------------------------

  Map<String, Object?> _metadataWith(
    Map<String, Object?> metadata, {
    int? timePs,
    String? designId,
  }) {
    final merged = <String, Object?>{...metadata};
    if (timePs != null) merged[cxpTimePsMetadataKey] = timePs;
    if (designId != null) merged[cxpDesignIdMetadataKey] = designId;
    return merged;
  }

  /// The links a send goes to.
  List<_Link> _targets({
    CxpProbePeer? to,
    String? product,
    ElementKind? accepting,
  }) {
    if (to != null) {
      final link = _links[to.peerId];
      return link == null ? const <_Link>[] : <_Link>[link];
    }
    return <_Link>[
      for (final link in _links.values)
        if ((product == null || link.peer.isProduct(product)) &&
            (accepting == null || link.peer.accepts(accepting)))
          link,
    ];
  }

  Future<List<CxpProbeReply>> _ask(
    List<_Link> targets,
    CxpMessage request, {
    CxpProbePeer? to,
  }) async {
    if (_closed) {
      throw StateError('The CxpProbe is closed.');
    }
    if (targets.isEmpty && to != null) {
      return <CxpProbeReply>[
        CxpProbeReply(
          peer: to,
          outcome: CxpProbeOutcome.failed,
          reason: 'not connected',
        ),
      ];
    }
    return await Future.wait(<Future<CxpProbeReply>>[
      for (final link in targets) _askOne(link, request),
    ]);
  }

  Future<CxpProbeReply> _askOne(_Link link, CxpMessage request) async {
    final id = link.client.sendTracked(request);
    if (id == null) {
      return CxpProbeReply(
        peer: link.peer,
        outcome: CxpProbeOutcome.failed,
        reason: 'the link to the peer is closed',
      );
    }
    final key = _waiterKey(link.peer.peerId, id);
    final waiter = Completer<CxpProbeReply>();
    _waiters[key] = waiter;
    try {
      return await waiter.future.timeout(
        ackTimeout,
        onTimeout: () => CxpProbeReply(
          peer: link.peer,
          outcome: CxpProbeOutcome.unacknowledged,
          reason: 'no acknowledgement within $ackTimeout',
        ),
      );
    } on _LinkClosed catch (closed) {
      return CxpProbeReply(
        peer: link.peer,
        outcome: CxpProbeOutcome.failed,
        reason: closed.reason,
      );
    } finally {
      _waiters.remove(key);
    }
  }

  static String _waiterKey(String peerId, String messageId) =>
      '$peerId/$messageId';

  void _emit(CxpProbeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static String _newPeerId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = slug.isEmpty ? 'probe' : slug;
    // `<product>-<pid>-<started at>`, the convention of CXP §8.1, so the
    // id is a legal file name and never repeats between runs.
    return '$stem-$pid-${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// A connected peer, with the client that talks to it.
class _Link {
  _Link(this.peer, this.client);

  final CxpProbePeer peer;
  final LocalCxpClient client;
}

class _LinkClosed implements Exception {
  const _LinkClosed(this.reason);

  final String reason;
}

/// Receives what the connector's links carry and turns it into the probe's
/// state: peers joining and leaving, acknowledgements, selections, requests.
class _ProbeSink implements CxpLinkSink {
  _ProbeSink(this._probe);

  final CxpProbe _probe;

  @override
  void attachLinkedPeer(
    PeerIdentity peer,
    void Function(CxpMessage message) send,
  ) {
    LocalCxpClient? client;
    for (final candidate in _probe._clients) {
      if (candidate.isConnected &&
          candidate.remotePeer?.peerId == peer.peerId) {
        client = candidate;
        break;
      }
    }
    if (client == null) return;
    final link = _Link(CxpProbePeer(peer), client);
    _probe._links[peer.peerId] = link;
    _probe._emit(CxpPeerJoined(link.peer));
  }

  @override
  void detachLinkedPeer(String peerId) {
    final link = _probe._links.remove(peerId);
    if (link == null) return;
    final prefix = '$peerId/';
    for (final entry in _probe._waiters.entries.toList()) {
      if (entry.key.startsWith(prefix) && !entry.value.isCompleted) {
        entry.value.completeError(const _LinkClosed('the peer disconnected'));
      }
    }
    _probe._emit(CxpPeerLeft(link.peer));
  }

  @override
  void injectInbound(InboundCxpMessage inbound) {
    final link = _probe._links[inbound.from.peerId];
    if (link == null) return;
    final message = inbound.message;
    switch (message) {
      case RequestHighlightAck(:final inReplyTo, :final honored, :final reason):
        _answer(link, inReplyTo, honored: honored, reason: reason);
      case RequestOpenSourceAck(
        :final inReplyTo,
        :final honored,
        :final reason,
      ):
        _answer(link, inReplyTo, honored: honored, reason: reason);
      case RequestOpenArtifactAck(
        :final inReplyTo,
        :final honored,
        :final reason,
      ):
        _answer(link, inReplyTo, honored: honored, reason: reason);
      case ErrorResponse(:final inReplyTo, :final code, message: final text):
        _answer(link, inReplyTo, honored: false, reason: '$code: $text');
      case NotifySelection():
        _probe._emit(
          CxpSelectionReceived(
            peer: link.peer,
            elements: message.elements,
            displayName: message.displayName,
            coordinate: message.coordinate,
            metadata: message.metadata,
          ),
        );
      case RequestHighlight():
        unawaited(_serve(link, inbound.envelope.messageId, message));
      case RequestOpenSource():
        unawaited(_serve(link, inbound.envelope.messageId, message));
      case RequestOpenArtifact():
        _declineArtifact(link, inbound.envelope.messageId, message);
      default:
        // A message kind this client has no use for (a peer's broadcast of
        // another's request, say) is ignored, as CXP §6.1 allows.
        break;
    }
  }

  void _answer(
    _Link link,
    String inReplyTo, {
    required bool honored,
    String? reason,
  }) {
    final waiter =
        _probe._waiters[CxpProbe._waiterKey(link.peer.peerId, inReplyTo)];
    if (waiter == null || waiter.isCompleted) return;
    waiter.complete(
      CxpProbeReply(
        peer: link.peer,
        outcome: honored ? CxpProbeOutcome.honored : CxpProbeOutcome.declined,
        reason: reason,
      ),
    );
  }

  /// Answers a request a peer sent the probe, through the handler.
  Future<void> _serve(_Link link, String messageId, CxpMessage request) async {
    CxpHandlerResult result;
    final handler = _probe._handler;
    if (handler == null) {
      result = const CxpHandlerResult.declined(
        'this program does not act on requests from peers',
      );
    } else {
      try {
        result = request is RequestHighlight
            ? await handler.highlight(link.peer, request)
            : await handler.openSource(link.peer, request as RequestOpenSource);
      } on Object catch (error) {
        result = CxpHandlerResult.declined('the handler failed: $error');
      }
    }
    final ack = request is RequestHighlight
        ? RequestHighlightAck(
            inReplyTo: messageId,
            honored: result.honored,
            reason: result.reason,
          )
        : RequestOpenSourceAck(
            inReplyTo: messageId,
            honored: result.honored,
            reason: result.reason,
          );
    link.client.send(ack);
    _probe._emit(
      CxpRequestReceived(peer: link.peer, request: request, result: result),
    );
  }

  void _declineArtifact(
    _Link link,
    String messageId,
    RequestOpenArtifact request,
  ) {
    const result = CxpHandlerResult.declined(
      'this program has no shared workspace to open artifacts from',
    );
    link.client.send(
      RequestOpenArtifactAck(
        inReplyTo: messageId,
        honored: false,
        reason: result.reason,
      ),
    );
    _probe._emit(
      CxpRequestReceived(peer: link.peer, request: request, result: result),
    );
  }
}
