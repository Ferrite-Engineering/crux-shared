// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_single_instance/crux_single_instance.dart';
import 'package:crux_single_instance/src/protocol.dart';
import 'package:crux_single_instance/src/rendezvous.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _appId = 'com.example.viewer';

void main() {
  final transports = [
    if (!Platform.isWindows) SingleInstanceTransport.unixSocket,
    SingleInstanceTransport.loopbackTcp,
  ];

  for (final transport in transports) {
    group(transport.name, () {
      late Directory tmp;
      late String dir;
      final opened = <SingleInstancePrimary>[];

      setUp(() {
        // Short: a Unix socket path has to fit in about a hundred bytes.
        tmp = Directory.systemTemp.createTempSync('csi');
        dir = p.join(tmp.path, 'r');
      });

      tearDown(() async {
        for (final primary in opened) {
          await primary.close();
        }
        opened.clear();
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      SingleInstance instance({
        Duration timeout = const Duration(seconds: 3),
        int maxLinkBytes = 256,
      }) => SingleInstance(
        appId: _appId,
        policy: SingleInstanceLinkPolicy(
          schemes: const ['viewer'],
          maxLinkBytes: maxLinkBytes,
        ),
        directory: dir,
        transport: transport,
        timeout: timeout,
      );

      SingleInstanceRendezvous rendezvous() => SingleInstanceRendezvous(
        directory: dir,
        appId: _appId,
        transport: transport,
      );

      Future<SingleInstancePrimary> primary() async {
        final claim = await instance().claim();
        expect(claim, isA<SingleInstancePrimary>());
        final primary = claim as SingleInstancePrimary;
        opened.add(primary);
        return primary;
      }

      test('the first instance becomes the running one', () async {
        final claim = await instance().claim(link: 'viewer://open?x=1');

        expect(claim, isA<SingleInstancePrimary>());
        final primary = claim as SingleInstancePrimary;
        opened.add(primary);
        expect(File(rendezvous().advertPath).existsSync(), isTrue);
        if (transport == SingleInstanceTransport.loopbackTcp) {
          expect(primary.address.isLoopback, isTrue);
          expect(primary.address.type, InternetAddressType.IPv4);
        } else {
          expect(primary.address.type, InternetAddressType.unix);
          expect(primary.address.address, rendezvous().socketPath);
        }
      });

      test('a second instance delivers its link and is told to exit', () async {
        final running = await primary();
        final received = running.links.first;

        final second = await instance().claim(link: 'viewer://open?x=2');

        expect(second, isA<SingleInstanceDelivered>());
        expect(await received, 'viewer://open?x=2');
      });

      test('a second instance with no link runs on its own', () async {
        await primary();

        final second = await instance().claim();

        expect(
          second,
          isA<SingleInstanceStandalone>().having(
            (s) => s.reason,
            'reason',
            SingleInstanceStandaloneReason.anotherInstanceRuns,
          ),
        );
      });

      test('closing hands the role to the next launch', () async {
        final running = await primary();
        await running.close();
        opened.remove(running);

        expect(File(rendezvous().advertPath).existsSync(), isFalse);
        expect(
          FileSystemEntity.typeSync(rendezvous().socketPath),
          FileSystemEntityType.notFound,
        );
        final next = await instance().claim(link: 'viewer://open?x=3');
        expect(next, isA<SingleInstancePrimary>());
        opened.add(next as SingleInstancePrimary);
      });

      // An instance that died leaves its socket and advert behind but not its
      // lock, which the operating system releases with the process.
      test('stale files from an ended instance are replaced', () async {
        Directory(dir).createSync(recursive: true);
        File(rendezvous().socketPath).writeAsStringSync('stale');
        SingleInstanceAdvert(
          token: generateSingleInstanceSecret(),
          port: transport == SingleInstanceTransport.loopbackTcp ? 9 : null,
        ).write(rendezvous().advertPath);

        final running = await primary();
        final received = running.links.first;
        final second = await instance().claim(link: 'viewer://open?x=4');

        expect(second, isA<SingleInstanceDelivered>());
        expect(await received, 'viewer://open?x=4');
      });

      test('a launch holding the wrong token sends nothing', () async {
        final running = await primary();
        final links = <String>[];
        running.links.listen(links.add);
        final real = SingleInstanceAdvert.read(rendezvous().advertPath)!;
        SingleInstanceAdvert(
          token: generateSingleInstanceSecret(),
          port: real.port,
        ).write(rendezvous().advertPath);

        final second = await instance(
          timeout: const Duration(milliseconds: 300),
        ).claim(link: 'viewer://open?x=5');

        expect(
          second,
          isA<SingleInstanceStandalone>().having(
            (s) => s.reason,
            'reason',
            SingleInstanceStandaloneReason.timedOut,
          ),
        );
        await pumpEventQueue();
        expect(links, isEmpty);
      });

      test('a peer proving the wrong token is refused', () async {
        final running = await primary();
        final links = <String>[];
        running.links.listen(links.add);

        final answer = await _exchange(
          rendezvous(),
          token: generateSingleInstanceSecret(),
          link: 'viewer://open?x=6',
        );

        expect(answer, kSingleInstanceRefused);
        await pumpEventQueue();
        expect(links, isEmpty);
      });

      test('the running instance proves it holds the token', () async {
        await primary();
        final advert = SingleInstanceAdvert.read(rendezvous().advertPath)!;

        final answer = await _exchange(
          rendezvous(),
          token: advert.token,
          link: 'viewer://open?x=7',
        );

        expect(answer, kSingleInstanceAccepted);
      });

      test('an oversized payload is refused and dropped', () async {
        final running = await primary();
        final links = <String>[];
        running.links.listen(links.add);
        final advert = SingleInstanceAdvert.read(rendezvous().advertPath)!;

        final answer = await _exchange(
          rendezvous(),
          token: advert.token,
          link: 'viewer://open?x=${'a' * 70000}',
        );

        expect(answer, anyOf(kSingleInstanceRefused, isNull));
        await pumpEventQueue();
        expect(links, isEmpty);
      });

      test('a link over the bound is not sent at all', () async {
        await primary();

        final claim = await instance().claim(
          link: 'viewer://open?x=${'a' * 300}',
        );

        expect(
          claim,
          isA<SingleInstanceStandalone>().having(
            (s) => s.reason,
            'reason',
            SingleInstanceStandaloneReason.linkRejected,
          ),
        );
      });

      test('a link of another scheme is refused by the server', () async {
        final running = await primary();
        final links = <String>[];
        running.links.listen(links.add);
        final advert = SingleInstanceAdvert.read(rendezvous().advertPath)!;

        for (final link in [
          'https://example.com/',
          'viewer://a viewer://b',
          'not a url',
        ]) {
          final answer = await _exchange(
            rendezvous(),
            token: advert.token,
            link: link,
          );
          expect(answer, kSingleInstanceRefused, reason: link);
        }
        await pumpEventQueue();
        expect(links, isEmpty);
      });

      test('a launch with a link of another scheme keeps it', () async {
        await primary();

        final claim = await instance().claim(link: 'https://example.com/');

        expect(
          claim,
          isA<SingleInstanceStandalone>().having(
            (s) => s.reason,
            'reason',
            SingleInstanceStandaloneReason.linkRejected,
          ),
        );
      });

      test('a malformed greeting is refused', () async {
        await primary();
        final socket = await _connect(rendezvous());
        final reply = socket.cast<List<int>>().transform(utf8.decoder).join();
        socket.write('hello there\n');

        expect(await reply, '$kSingleInstanceRefused\n');
        socket.destroy();
      });

      test('concurrent launches elect one running instance', () async {
        final claims = await Future.wait([
          for (var i = 0; i < 6; i++)
            instance().claim(link: 'viewer://open?n=$i'),
        ]);

        final primaries = claims.whereType<SingleInstancePrimary>().toList();
        expect(primaries, hasLength(1));
        opened.addAll(primaries);
        expect(claims.whereType<SingleInstanceDelivered>(), hasLength(5));
        final received = await primaries.single.links.take(5).toList();
        expect(received.toSet(), hasLength(5));
      });

      test('an application id that cannot name a file is refused', () async {
        final claim = await SingleInstance(
          appId: '../escape',
          policy: SingleInstanceLinkPolicy(schemes: const ['viewer']),
          directory: dir,
          transport: transport,
        ).claim();

        expect(
          claim,
          isA<SingleInstanceStandalone>().having(
            (s) => s.reason,
            'reason',
            SingleInstanceStandaloneReason.unavailable,
          ),
        );
      });
    });
  }

  test(
    'a socket path too long for the platform is refused',
    () async {
      final tmp = Directory.systemTemp.createTempSync('csi');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final claim = await SingleInstance(
        appId: _appId,
        policy: SingleInstanceLinkPolicy(schemes: const ['viewer']),
        directory: p.join(tmp.path, 'd' * 120),
        transport: SingleInstanceTransport.unixSocket,
      ).claim();

      expect(
        claim,
        isA<SingleInstanceStandalone>().having(
          (s) => s.reason,
          'reason',
          SingleInstanceStandaloneReason.unavailable,
        ),
      );
    },
    skip: Platform.isWindows ? 'no Unix domain sockets' : false,
  );
}

Future<Socket> _connect(SingleInstanceRendezvous rendezvous) {
  if (rendezvous.transport == SingleInstanceTransport.unixSocket) {
    return Socket.connect(
      InternetAddress(rendezvous.socketPath, type: InternetAddressType.unix),
      0,
    );
  }
  final advert = SingleInstanceAdvert.read(rendezvous.advertPath)!;
  return Socket.connect(InternetAddress.loopbackIPv4, advert.port!);
}

/// Speaks the protocol as a launching process would, holding [token], and
/// returns the running instance's final answer, or null when it closed the
/// connection without one. Throws when the running instance's own proof does
/// not match [token]: a launch would stop there.
Future<String?> _exchange(
  SingleInstanceRendezvous rendezvous, {
  required String token,
  required String link,
}) async {
  final socket = await _connect(rendezvous);
  final lines = StreamIterator(
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );
  try {
    final clientNonce = generateSingleInstanceSecret();
    socket.write('$kSingleInstanceProtocol $clientNonce\n');
    if (!await lines.moveNext()) return null;
    final [serverNonce, serverProof] = lines.current.split(' ');
    final proofMatches =
        serverProof ==
        singleInstanceServerProof(
          token: token,
          clientNonce: clientNonce,
          serverNonce: serverNonce,
        );
    final proof = singleInstanceClientProof(
      token: token,
      clientNonce: clientNonce,
      serverNonce: serverNonce,
      link: link,
    );
    try {
      socket.add(Uint8List.fromList(utf8.encode('$proof $link\n')));
      await socket.flush();
    } on SocketException {
      // The running instance may close before an oversized line is written.
    }
    final answered = await lines.moveNext().catchError((Object _) => false);
    final answer = answered ? lines.current : null;
    if (!proofMatches && answer == kSingleInstanceAccepted) {
      fail('accepted a peer that cannot have proved the token');
    }
    return answer;
  } finally {
    await lines.cancel();
    socket.destroy();
  }
}
