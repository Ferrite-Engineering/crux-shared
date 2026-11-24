// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _serverId = PeerIdentity(
  peerId: 'wavecrux-time-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

const PeerIdentity _rawId = PeerIdentity(
  peerId: 'raw-time-2',
  productName: 'rawpeer',
  productVersion: '0.0.0',
);

const Map<String, Object?> _signal = <String, Object?>{
  'kind': 'signal',
  'path': 'top.cpu.alu.result[7:0]',
};

/// CXP §9.3.3 (rev. 11) at the listener: the optional `time` field of
/// `request_highlight` and `notify_selection`, sent as raw JSON by a peer
/// written from the specification, over a real socket.
///
/// A peer that sends no time is served as before; a time in the grammar is
/// dispatched to the product; a time outside it is `malformed_payload` and
/// the connection survives; a retraction's time is never an error.
void main() {
  late LocalCxpServer server;
  late _RawPeer raw;
  late List<InboundCxpMessage> inbound;

  setUp(() async {
    server = LocalCxpServer(selfIdentity: _serverId);
    await server.start();
    inbound = <InboundCxpMessage>[];
    server.inbound.listen(inbound.add);
    raw = await _RawPeer.connect(server.boundPort!)
      ..send(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        messageId: 'hello-1',
      );
    await pollUntil(
      () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
      reason: 'handshake must complete',
    );
  });

  tearDown(() async {
    await raw.close();
    await server.stop();
  });

  /// Sends a well-formed highlight after the frames under test and waits for
  /// it: frames on one socket are handled in order, so once the marker is
  /// dispatched every answer to the earlier frames has been written.
  Future<void> drain() async {
    raw.send(
      kind: CxpMessageKind.requestHighlight,
      payload: const <String, Object?>{
        'element': {'kind': 'signal', 'path': 'marker'},
      },
      messageId: 'marker',
    );
    await pollUntil(
      () => inbound.any(
        (m) =>
            m.message is RequestHighlight &&
            (m.message as RequestHighlight).element.path == 'marker',
      ),
      reason: 'the ordering marker must dispatch',
    );
  }

  RequestHighlight highlightWithId(String id) =>
      inbound.firstWhere((m) => m.envelope.messageId == id).message
          as RequestHighlight;

  test('a peer that sends no time is served as before', () async {
    // The §9.3.2 example, as a revision 10 peer sends it.
    raw.send(
      kind: CxpMessageKind.requestHighlight,
      payload: const <String, Object?>{
        'element': _signal,
        'metadata': {'crux.time_ps': 41250},
      },
      messageId: 'no-time',
    );
    await drain();

    expect(raw.ofKind(CxpMessageKind.errorResponse), isEmpty);
    final request = highlightWithId('no-time');
    expect(request.time, isNull);
    expect(request.metadata, {'crux.time_ps': 41250});
  });

  test('a time in the grammar reaches the product, exact', () async {
    raw
      ..send(
        kind: CxpMessageKind.requestHighlight,
        payload: const <String, Object?>{'element': _signal, 'time': '1.5us'},
        messageId: 'unit',
      )
      ..send(
        kind: CxpMessageKind.requestHighlight,
        payload: const <String, Object?>{'element': _signal, 'time': '42'},
        messageId: 'ticks',
      )
      ..send(
        kind: CxpMessageKind.notifySelection,
        payload: const <String, Object?>{
          'elements': [_signal],
          'time': '41250ps',
        },
        messageId: 'selection',
      );
    await drain();

    expect(raw.ofKind(CxpMessageKind.errorResponse), isEmpty);
    // 1.5 us = 1500 ns, by hand.
    expect(
      highlightWithId('unit').time,
      CxpTime.seconds(BigInt.from(1500), -9),
    );
    expect(highlightWithId('ticks').time, CxpTime.ticks(42));
    final selection =
        inbound.firstWhere((m) => m.envelope.messageId == 'selection').message
            as NotifySelection;
    expect(selection.time, CxpTime.picoseconds(41250));
  });

  test(
    'a time outside the grammar is malformed_payload, and the connection '
    'survives',
    () async {
      const bad = <Object?>[41250, '1.5', '-1ns', '1 ns', '1NS', ''];
      for (var i = 0; i < bad.length; i++) {
        raw.send(
          kind: CxpMessageKind.requestHighlight,
          payload: <String, Object?>{'element': _signal, 'time': bad[i]},
          messageId: 'bad-$i',
        );
      }
      await drain();
      // The marker dispatching on the server only proves the answers were
      // written; the raw client reads them asynchronously, so wait for them.
      await pollUntil(
        () =>
            raw.errorPayloads(CxpErrorCode.malformedPayload).length >=
            bad.length,
        reason: 'every malformed time is answered',
      );

      final errors = raw.errorPayloads(CxpErrorCode.malformedPayload);
      expect(
        [for (final e in errors) e['in_reply_to']],
        [for (var i = 0; i < bad.length; i++) 'bad-$i'],
      );
      expect(
        inbound.where((m) => m.envelope.messageId.startsWith('bad-')),
        isEmpty,
        reason: 'a highlight with a malformed time is not dispatched',
      );
    },
  );

  test('a retraction with a time is never an error', () async {
    raw.send(
      kind: CxpMessageKind.notifySelection,
      payload: const <String, Object?>{
        'elements': <Object?>[],
        'time': 'not a time',
      },
      messageId: 'retraction',
    );
    await drain();

    expect(raw.ofKind(CxpMessageKind.errorResponse), isEmpty);
    final retraction =
        inbound.firstWhere((m) => m.envelope.messageId == 'retraction').message
            as NotifySelection;
    expect(retraction.elements, isEmpty);
    expect(retraction.time, isNull);
  });
}

/// A raw TCP peer speaking newline-JSON, written from the specification.
class _RawPeer {
  _RawPeer._(this._socket) {
    _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isEmpty) return;
            _envelopes.add((jsonDecode(line) as Map).cast<String, Object?>());
          },
          onError: (Object _) {},
          cancelOnError: false,
        );
  }

  static Future<_RawPeer> connect(int port) async =>
      _RawPeer._(await Socket.connect('127.0.0.1', port));

  final Socket _socket;
  final List<Map<String, Object?>> _envelopes = <Map<String, Object?>>[];

  void send({
    required String kind,
    required Map<String, Object?> payload,
    required String messageId,
  }) {
    _socket.write(
      '${jsonEncode(<String, Object?>{
        'cxp_version': '1.3',
        'message_id': messageId,
        'from': _rawId.peerId,
        'kind': kind,
        'payload': payload,
      })}\n',
    );
  }

  Iterable<Map<String, Object?>> ofKind(String kind) =>
      _envelopes.where((e) => e['kind'] == kind);

  List<Map<String, Object?>> errorPayloads(String code) => [
    for (final envelope in ofKind(CxpMessageKind.errorResponse))
      if ((envelope['payload']! as Map).cast<String, Object?>()['code'] == code)
        (envelope['payload']! as Map).cast<String, Object?>(),
  ];

  Future<void> close() async {
    _socket.destroy();
  }
}
