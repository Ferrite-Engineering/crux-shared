// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edacrux_cxp/edacrux_cxp.dart';
import 'package:test/test.dart';

import '../conformance/poll.dart';
import 'fake_peer.dart';

/// The probe against peers written from the specification alone
/// (`fake_peer.dart`): what it puts on the wire is compared with the
/// examples in the specification, and what a peer says back is turned into
/// the replies and events the API promises.
void main() {
  late Directory directory;
  late List<FakePeer> peers;
  late List<CxpProbe> probes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cxp_probe_');
    peers = <FakePeer>[];
    probes = <CxpProbe>[];
  });

  tearDown(() async {
    for (final probe in probes) {
      await probe.close();
    }
    for (final peer in peers) {
      await peer.stop();
    }
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Future<FakePeer> peer({
    String productName = 'wavecrux',
    Set<String> capabilities = const <String>{},
    Map<String, Object?>? Function(String, Map<String, Object?>)? onRequest,
    bool proveBack = true,
    String host = '127.0.0.1',
    String? version = '1.3',
    String token = 'a-token-of-at-least-sixteen-bytes',
  }) async {
    final created = await FakePeer.start(
      directory: directory,
      productName: productName,
      capabilities: capabilities,
      onRequest: onRequest,
      proveBack: proveBack,
      manifestHost: host,
      manifestVersion: version,
      token: token,
    );
    peers.add(created);
    return created;
  }

  Future<CxpProbe> probe({
    CxpProbeRequestHandler? handler,
    Duration ackTimeout = const Duration(seconds: 3),
    List<CxpSubscription> subscriptions = cxpProbeDefaultSubscriptions,
    String name = 'rohd-sim',
  }) async {
    final started = await CxpProbe.start(
      name: name,
      version: '9.9.9',
      manifestDirectory: directory.path,
      handler: handler,
      ackTimeout: ackTimeout,
      subscriptions: subscriptions,
      scanInterval: const Duration(milliseconds: 100),
      retryInterval: const Duration(milliseconds: 100),
    );
    probes.add(started);
    return started;
  }

  group('connecting', () {
    test(
      'finds a running app, completes the 1.3 handshake and lists it',
      () async {
        final wave = await peer(
          capabilities: {'cxp.accepts:signal', 'cxp.accepts:marker'},
        );
        final p = await probe();

        final found = await p.waitForPeer(product: 'WaveCrux');
        expect(found.peerId, wave.peerId);
        expect(found.productName, 'wavecrux');
        expect(found.productVersion, '1.2.3');
        expect(p.peers, [found]);

        // §7.4, 1.3: the manifest announced 1.3, so the hello carries a nonce
        // and a proof, never the token itself.
        expect(wave.hellos, hasLength(1));
        final hello = wave.hellos.single;
        expect(hello.containsKey('token'), isFalse);
        expect(hello['nonce'], isA<String>());
        expect(
          hello['proof'],
          wave.proof('cxp-hello', hello['nonce']! as String),
        );
        final identity = (hello['identity']! as Map).cast<String, Object?>();
        expect(identity['product_name'], 'rohd-sim');
        expect(identity['product_version'], '9.9.9');
        expect(identity['peer_id'], startsWith('rohd-sim-'));
      },
    );

    test(
      'presents the token as 1.2 did to a manifest that announces no version',
      () async {
        final old = await peer(version: null);
        final p = await probe();

        await p.waitForPeer();
        final hello = old.hellos.single;
        expect(hello['token'], old.token);
        expect(hello.containsKey('proof'), isFalse);
      },
    );

    test(
      'subscribes to selections by default, and to nothing when told not to',
      () async {
        final a = await peer();
        final p = await probe();
        await p.waitForPeer();
        await pollUntil(
          () => a.receivedOf('subscribe').isNotEmpty,
          reason: 'the probe announces its subscription',
        );
        final payload = (a.receivedOf('subscribe').single['payload']! as Map)
            .cast<String, Object?>();
        expect(payload['subscriptions'], [
          {'message_kind': 'notify_selection', 'element_kinds': <Object?>[]},
        ]);

        final quiet = await probe(subscriptions: const [], name: 'quiet');
        await quiet.waitForPeer();
        await pollUntil(
          () => a.receivedOf('subscribe').length == 2,
          reason: 'the second probe announces an empty subscription',
        );
        final second = (a.receivedOf('subscribe').last['payload']! as Map)
            .cast<String, Object?>();
        expect(second['subscriptions'], isEmpty);
      },
    );

    test(
      'reports a peer that refuses the handshake instead of listing it',
      () async {
        // A listener that does not prove it holds the token is whatever bound
        // the port, not the peer that wrote the manifest (§7.4).
        await peer(proveBack: false);
        final p = await probe();
        final failure = await p.dialFailures.first.timeout(
          const Duration(seconds: 5),
        );
        expect(failure.error, isA<CxpHandshakeException>());
        expect((failure.error as CxpHandshakeException).code, 'unauthorized');
        expect(p.peers, isEmpty);
      },
    );

    test('refuses to dial a manifest that names a non-loopback host', () async {
      final far = await peer(host: '192.0.2.1');
      final p = await probe();
      final failure = await p.dialFailures.first.timeout(
        const Duration(seconds: 5),
      );
      expect(failure.error, isA<CxpDialRefusedException>());
      expect(p.peers, isEmpty);
      expect(far.hellos, isEmpty);
    });

    test('waitForPeer times out when no such app is running', () async {
      await peer(productName: 'netcrux');
      final p = await probe();
      await p.waitForPeer(product: 'netcrux');
      await expectLater(
        p.waitForPeer(
          product: 'wavecrux',
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test(
      'a peer that appears later is dialled, and one that leaves is reported',
      () async {
        final p = await probe();
        final events = <CxpProbeEvent>[];
        p.events.listen(events.add);
        expect(p.peers, isEmpty);

        final late = await peer(productName: 'netcrux');
        await p.waitForPeer(product: 'netcrux');
        await late.dropClients();
        await pollUntil(
          () => events.whereType<CxpPeerLeft>().isNotEmpty,
          reason: 'the dropped link is reported',
        );
        expect(
          events.whereType<CxpPeerJoined>().single.peer.peerId,
          late.peerId,
        );
        expect(events.whereType<CxpPeerLeft>().single.peer.peerId, late.peerId);
      },
    );

    test('close says goodbye to the peer and is safe to repeat', () async {
      final a = await peer();
      final p = await probe();
      await p.waitForPeer();
      await p.close();
      await pollUntil(() => a.goodbyes == 1, reason: 'a goodbye arrives');
      await p.close();
      expect(p.peers, isEmpty);
      await expectLater(p.showSignal('top.x'), throwsStateError);
    });
  });

  group('the requests it sends are the ones the specification shows', () {
    test(
      'showSignal is the §9.4 request_highlight, with time and design id',
      () async {
        final wave = await peer(capabilities: {'cxp.accepts:signal'});
        final p = await probe();
        await p.waitForPeer();

        final replies = await p.showSignal(
          'top.cpu.alu.result[7:0]',
          timePs: 41250,
          designId: '0123456789abcdef',
        );

        expect(replies, hasLength(1));
        expect(replies.single.outcome, CxpProbeOutcome.honored);
        expect(replies.single.honored, isTrue);
        expect(replies.single.peer.peerId, wave.peerId);

        final envelope = wave.receivedOf('request_highlight').single;
        expect(envelope['cxp_version'], '1.3');
        expect(envelope['from'], startsWith('rohd-sim-'));
        expect(envelope['message_id'], isA<String>());
        expect(envelope['payload'], {
          'element': {'kind': 'signal', 'path': 'top.cpu.alu.result[7:0]'},
          'metadata': {'time_ps': 41250, 'crux.design_id': '0123456789abcdef'},
        });
      },
    );

    test('a net, a cell and a scope go out as their own kinds', () async {
      final net = await peer(productName: 'netcrux');
      final p = await probe();
      await p.waitForPeer();

      await p.highlightNet('top.cpu.alu.result');
      await p.highlightCell('top.u_alu.add_1');
      await p.openScope('top.cpu');

      final payloads = [
        for (final e in net.receivedOf('request_highlight'))
          (e['payload']! as Map)['element'],
      ];
      expect(payloads, [
        {'kind': 'net', 'path': 'top.cpu.alu.result'},
        {'kind': 'cell', 'path': 'top.u_alu.add_1'},
        {'kind': 'scope', 'path': 'top.cpu'},
      ]);
      // No metadata was given, so none is sent (§9.4: the field is optional).
      expect(
        (net.receivedOf('request_highlight').first['payload']! as Map)
            .containsKey('metadata'),
        isFalse,
      );
    });

    test('openSource is the §9.6 request_open_source', () async {
      final net = await peer(productName: 'netcrux');
      final p = await probe();
      await p.waitForPeer();

      final replies = await p.openSource('/src/cpu/alu.sv', 214, column: 9);

      expect(replies.single.honored, isTrue);
      expect(net.receivedOf('request_open_source').single['payload'], {
        'file_path': '/src/cpu/alu.sv',
        'line': 214,
        'column': 9,
      });
      expect(() => p.openSource('/src/a.sv', 0), throwsArgumentError);
      expect(
        () => p.openSource('/src/a.sv', 1, column: 0),
        throwsArgumentError,
      );
    });

    test(
      'select is a §9.3 notify_selection, and clearSelection a retraction',
      () async {
        final wave = await peer();
        final p = await probe();
        await p.waitForPeer();

        final sentTo = await p.select(
          [const ElementId(kind: ElementKind.signal, path: 'top.clk')],
          displayName: 'clk',
          designId: 'abc',
        );
        final cleared = await p.clearSelection();

        expect(sentTo.single.peerId, wave.peerId);
        expect(cleared.single.peerId, wave.peerId);
        await pollUntil(
          () => wave.receivedOf('notify_selection').length == 2,
          reason: 'both selections arrive',
        );
        final selections = wave.receivedOf('notify_selection');
        expect(selections.first['payload'], {
          'elements': [
            {'kind': 'signal', 'path': 'top.clk'},
          ],
          'display_name': 'clk',
          'metadata': {'crux.design_id': 'abc'},
        });
        // An empty array is a retraction, not a malformed payload (§9.3).
        expect(selections.last['payload'], {'elements': <Object?>[]});
      },
    );

    test(
      'a message id is unique per request, so an ack names its request',
      () async {
        final wave = await peer();
        final p = await probe();
        await p.waitForPeer();
        await p.showSignal('top.a');
        await p.showSignal('top.b');
        final ids = {
          for (final e in wave.receivedOf('request_highlight')) e['message_id'],
        };
        expect(ids, hasLength(2));
      },
    );
  });

  group('who a request goes to', () {
    test(
      'only peers that accept the kind, by the cxp.accepts convention',
      () async {
        final wave = await peer(
          capabilities: {'cxp.accepts:signal', 'cxp.accepts:marker'},
        );
        final net = await peer(
          productName: 'netcrux',
          capabilities: {'cxp.accepts:net', 'cxp.accepts:cell'},
        );
        final any = await peer(productName: 'othertool');
        final p = await probe();
        await pollUntil(() => p.peers.length == 3, reason: 'all three connect');

        final signal = await p.showSignal('top.a');
        expect(
          signal.map((r) => r.peer.productName).toSet(),
          {'wavecrux', 'othertool'},
          reason:
              'netcrux advertises net and cell only; the tool that '
              'advertises nothing is sent whatever',
        );

        final cell = await p.highlightCell('top.u_add');
        expect(
          cell.map((r) => r.peer.productName).toSet(),
          {'netcrux', 'othertool'},
        );

        expect(wave.receivedOf('request_highlight'), hasLength(1));
        expect(net.receivedOf('request_highlight'), hasLength(1));
        expect(any.receivedOf('request_highlight'), hasLength(2));
      },
    );

    test('a kind nobody accepts is an empty answer, not an error', () async {
      await peer(capabilities: {'cxp.accepts:signal'});
      final p = await probe();
      await p.waitForPeer();
      expect(await p.highlightCell('top.u_add'), isEmpty);
    });

    test(
      'product narrows the audience, and to names one peer outright',
      () async {
        final wave = await peer(capabilities: {'cxp.accepts:signal'});
        final net = await peer(
          productName: 'netcrux',
          capabilities: {'cxp.accepts:signal'},
        );
        final p = await probe();
        await pollUntil(() => p.peers.length == 2, reason: 'both connect');

        final onlyNet = await p.showSignal('top.a', product: 'NETCRUX');
        expect(onlyNet.single.peer.peerId, net.peerId);

        final waveRef = p.peers.firstWhere((x) => x.peerId == wave.peerId);
        // Sent to a named peer whatever it advertises (the peer will say so).
        final forced = await p.highlightCell('top.u_add', to: waveRef);
        expect(forced.single.peer.peerId, wave.peerId);
        expect(wave.receivedOf('request_highlight'), hasLength(1));
      },
    );

    test(
      'a request to a peer that is gone fails instead of throwing',
      () async {
        final wave = await peer();
        final p = await probe();
        final ref = await p.waitForPeer();
        await wave.dropClients();
        await pollUntil(() => p.peers.isEmpty, reason: 'the link is dropped');
        final replies = await p.showSignal('top.a', to: ref);
        expect(replies.single.outcome, CxpProbeOutcome.failed);
        expect(replies.single.reason, 'not connected');
      },
    );
  });

  group('how a peer answers', () {
    test('honored false is declined, with the peer reason', () async {
      await peer(
        onRequest: (_, _) => {
          'honored': false,
          'reason': 'net not present in the loaded netlist',
        },
      );
      final p = await probe();
      await p.waitForPeer();
      final reply = (await p.showSignal('top.nope')).single;
      expect(reply.outcome, CxpProbeOutcome.declined);
      expect(reply.honored, isFalse);
      expect(reply.reason, 'net not present in the loaded netlist');
    });

    test('no answer within the timeout is unacknowledged', () async {
      await peer(onRequest: (_, _) => null);
      final p = await probe(ackTimeout: const Duration(milliseconds: 200));
      await p.waitForPeer();
      final reply = (await p.showSignal('top.a')).single;
      expect(reply.outcome, CxpProbeOutcome.unacknowledged);
    });

    test('a peer that disconnects mid-request fails it at once', () async {
      late FakePeer gone;
      gone = await peer(
        onRequest: (_, _) {
          unawaited(gone.dropClients());
          return null;
        },
      );
      final p = await probe(ackTimeout: const Duration(seconds: 30));
      await p.waitForPeer();
      final reply = (await p.showSignal('top.a')).single;
      expect(reply.outcome, CxpProbeOutcome.failed);
    });

    test('an error_response that names the request declines it', () async {
      final wave = await peer(onRequest: (_, _) => null);
      final p = await probe();
      await p.waitForPeer();
      final pending = p.openSource('/src/a.sv', 3);
      await pollUntil(
        () => wave.receivedOf('request_open_source').isNotEmpty,
        reason: 'the request arrives',
      );
      final id = wave.receivedOf('request_open_source').single['message_id'];
      wave.send('error_response', {
        'code': 'unsupported',
        'message': 'no editor configured',
        'in_reply_to': id,
      });
      final reply = (await pending).single;
      expect(reply.outcome, CxpProbeOutcome.declined);
      expect(reply.reason, 'unsupported: no editor configured');
    });

    test('an ack for another request does not answer this one', () async {
      final wave = await peer(onRequest: (_, _) => null);
      final p = await probe(ackTimeout: const Duration(milliseconds: 300));
      await p.waitForPeer();
      final pending = p.showSignal('top.a');
      await pollUntil(
        () => wave.receivedOf('request_highlight').isNotEmpty,
        reason: 'the request arrives',
      );
      wave.send('request_highlight_ack', {
        'in_reply_to': 'some-other-request',
        'honored': true,
      });
      expect((await pending).single.outcome, CxpProbeOutcome.unacknowledged);
    });
  });

  group('what peers tell it', () {
    test(
      'a selection arrives as an event, a cleared one as a retraction',
      () async {
        final wave = await peer();
        final p = await probe();
        await p.waitForPeer();
        final seen = <CxpSelectionReceived>[];
        p.events
            .where((e) => e is CxpSelectionReceived)
            .cast<CxpSelectionReceived>()
            .listen(seen.add);

        wave
          ..send('notify_selection', {
            'elements': [
              {'kind': 'signal', 'path': 'top.cpu.alu.result[7:0]'},
            ],
            'display_name': 'alu.result',
            'metadata': {'time_ps': 41250},
          })
          ..send('notify_selection', {'elements': <Object?>[]});

        await pollUntil(
          () => seen.length == 2,
          reason: 'both selections arrive',
        );
        expect(seen.first.peer.peerId, wave.peerId);
        expect(seen.first.elements.single.path, 'top.cpu.alu.result[7:0]');
        expect(seen.first.elements.single.kind, ElementKind.signal);
        expect(seen.first.displayName, 'alu.result');
        expect(seen.first.metadata['time_ps'], 41250);
        expect(seen.first.isRetraction, isFalse);
        expect(seen.last.isRetraction, isTrue);
      },
    );

    test(
      'a peer request is declined with a reason when there is no handler',
      () async {
        final wave = await peer();
        final p = await probe();
        await p.waitForPeer();
        final requests = <CxpRequestReceived>[];
        p.events
            .where((e) => e is CxpRequestReceived)
            .cast<CxpRequestReceived>()
            .listen(requests.add);

        wave.send('request_highlight', {
          'element': {'kind': 'signal', 'path': 'top.a'},
        });
        await pollUntil(
          () => wave.receivedOf('request_highlight_ack').isNotEmpty,
          reason: 'the peer is answered',
        );
        final ack =
            wave.receivedOf('request_highlight_ack').single['payload']! as Map;
        expect(ack['honored'], isFalse);
        expect(ack['reason'], contains('does not act on requests'));
        expect(ack['in_reply_to'], startsWith('peer-'));
        await pollUntil(() => requests.isNotEmpty, reason: 'the event fires');
        expect(requests.single.result.honored, isFalse);
      },
    );

    test(
      'a handler answers requests, and a handler that throws declines them',
      () async {
        final wave = await peer();
        final handler = _Handler();
        final p = await probe(handler: handler);
        await p.waitForPeer();

        wave
          ..send('request_highlight', {
            'element': {'kind': 'net', 'path': 'top.n'},
          })
          ..send('request_open_source', {
            'file_path': '/src/a.sv',
            'line': 7,
          });
        await pollUntil(
          () =>
              wave.receivedOf('request_highlight_ack').isNotEmpty &&
              wave.receivedOf('request_open_source_ack').isNotEmpty,
          reason: 'both requests are answered',
        );
        expect(handler.highlights.single.element.path, 'top.n');
        expect(handler.sources.single.line, 7);
        expect(
          wave.receivedOf('request_highlight_ack').single['payload'],
          containsPair('honored', true),
        );
        final sourceAck =
            wave.receivedOf('request_open_source_ack').single['payload']!
                as Map;
        expect(sourceAck['honored'], isFalse);
        expect(sourceAck['reason'], contains('the handler failed'));
      },
    );

    test(
      'a request_open_artifact is declined: a probe has no workspace',
      () async {
        final wave = await peer();
        final p = await probe();
        await p.waitForPeer();
        wave.send('request_open_artifact', {
          'design_id': 'abc',
          'kind': 'waveform',
        });
        await pollUntil(
          () => wave.receivedOf('request_open_artifact_ack').isNotEmpty,
          reason: 'the peer is answered',
        );
        expect(
          wave.receivedOf('request_open_artifact_ack').single['payload'],
          containsPair('honored', false),
        );
      },
    );
  });

  group('the capability convention', () {
    test('CxpProbePeer.accepts follows CXP 8.1', () {
      const advertising = CxpProbePeer(
        PeerIdentity(
          peerId: 'a-1',
          productName: 'a',
          productVersion: '1',
          capabilities: {'cxp.accepts:net', 'wavecrux.signal_value'},
        ),
      );
      const silent = CxpProbePeer(
        PeerIdentity(
          peerId: 'b-1',
          productName: 'b',
          productVersion: '1',
          capabilities: {'wavecrux.signal_value'},
        ),
      );
      expect(advertising.accepts(ElementKind.net), isTrue);
      expect(advertising.accepts(ElementKind.signal), isFalse);
      // A kind from a later revision is matched by its wire name.
      expect(
        advertising.accepts(ElementKind('widget')),
        isFalse,
      );
      // Advertising nothing under cxp.accepts: means "send whatever".
      expect(silent.accepts(ElementKind.signal), isTrue);
      expect(
        cxpAcceptsCapability(ElementKind.timingPath),
        'cxp.accepts:timing_path',
      );
    });
  });

  test('the probe announces the revision it implements', () {
    expect(cxpProtocolVersion, '1.3');
    expect(cxpSpecificationRevision, 9);
    expect(cxpTimePsMetadataKey, 'time_ps');
    // The wire form of a hello is JSON the spec shows; round-trip a decode.
    final line = jsonEncode({
      'cxp_version': cxpProtocolVersion,
      'message_id': 'x',
      'from': 'a',
      'kind': 'goodbye',
      'payload': <String, Object?>{},
    });
    expect(
      CxpEnvelope.fromJson(jsonDecode(line) as Map<String, Object?>).kind,
      'goodbye',
    );
  });
}

class _Handler implements CxpProbeRequestHandler {
  final List<RequestHighlight> highlights = <RequestHighlight>[];
  final List<RequestOpenSource> sources = <RequestOpenSource>[];

  @override
  FutureOr<CxpHandlerResult> highlight(
    CxpProbePeer from,
    RequestHighlight request,
  ) {
    highlights.add(request);
    return const CxpHandlerResult.honored();
  }

  @override
  FutureOr<CxpHandlerResult> openSource(
    CxpProbePeer from,
    RequestOpenSource request,
  ) {
    sources.add(request);
    throw StateError('no editor');
  }
}
