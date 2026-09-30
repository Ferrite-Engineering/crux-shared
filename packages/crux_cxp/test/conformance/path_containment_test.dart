// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _serverId = PeerIdentity(
  peerId: 'wavecrux-contain-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

const PeerIdentity _peerId = PeerIdentity(
  peerId: 'netcrux-contain-2',
  productName: 'netcrux',
  productVersion: '0.0.0',
);

/// CXP §11's containment rule, enforced in the shared layer.
///
/// A receiver SHOULD resolve a peer-supplied path against the directories
/// the user has opened and refuse the rest, and MUST apply the same rule to
/// an artifact it resolved through its own records as to a `file_path` on
/// the wire. Before this the rule lived in the products, differently in
/// each (two enforced "absolute" on one of the two requests, two enforced
/// nothing). These cases pin the one rule, and the two places the shared
/// stack applies it: `LocalCxpServer` before dispatch, on both the accept
/// loop and the connector link, and `CxpWorkspaceStore` on what it
/// resolves.
void main() {
  late Directory tempDir;
  late Directory openRoot;
  late Directory otherRoot;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_cxp_contain_');
    openRoot = Directory(p.join(tempDir.path, 'open'))..createSync();
    otherRoot = Directory(p.join(tempDir.path, 'other'))..createSync();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  String inside(String name) => p.join(openRoot.path, name);
  String outside(String name) => p.join(otherRoot.path, name);

  group('CxpPathContainment', () {
    test('the floor rule: absolute and well-formed, nothing more', () {
      const rule = CxpPathContainment();
      expect(rule.refuse(inside('a.v')), isNull);
      expect(rule.refuse(outside('a.v')), isNull, reason: 'no roots set');
      expect(rule.refuse(''), isNotNull);
      expect(rule.refuse('   '), isNotNull);
      expect(rule.refuse('relative/a.v'), isNotNull);
      expect(rule.refuse('./a.v'), isNotNull);
      expect(rule.refuse('--install-extension'), isNotNull);
      expect(rule.refuse('a.v\x00'), isNotNull);
      if (Platform.isWindows) {
        expect(rule.refuse(r'\rooted\not\absolute.v'), isNotNull);
      }
    });

    test('with roots: inside is allowed, outside is refused', () {
      final rule = CxpPathContainment(roots: () => [openRoot.path]);
      expect(rule.refuse(inside('a.v')), isNull);
      expect(rule.refuse(inside(p.join('deep', 'er', 'a.v'))), isNull);
      expect(rule.refuse(openRoot.path), isNull, reason: 'the root itself');
      expect(rule.refuse(outside('a.v')), isNotNull);
      expect(rule.refuse(tempDir.path), isNotNull, reason: 'the parent');
      expect(rule.refuse('/'), isNotNull);
    });

    test('a `..` walk out of a root is refused', () {
      final rule = CxpPathContainment(roots: () => [openRoot.path]);
      final walk = p.join(openRoot.path, '..', 'other', 'a.v');
      expect(rule.refuse(walk), isNotNull);
      Directory(inside('x')).createSync();
      expect(rule.allows(p.join(openRoot.path, 'x', '..', 'a.v')), isTrue);
    });

    test('the value checked is the value opened: no surrounding white '
        'space', () {
      // Trimming before the check let `" /etc/hosts"` pass as absolute
      // while the untrimmed string — relative as spelled — was dispatched.
      const floor = CxpPathContainment();
      final rule = CxpPathContainment(roots: () => [openRoot.path]);
      for (final spelled in <String>[
        ' ${inside('a.v')}',
        '${inside('a.v')} ',
        '\t${inside('a.v')}\n',
        '\u00a0${inside('a.v')}',
      ]) {
        expect(floor.refuse(spelled), isNotNull, reason: '"$spelled"');
        expect(rule.refuse(spelled), isNotNull, reason: '"$spelled"');
      }
      expect(floor.refuse(' /etc/hosts'), isNotNull);
      expect(
        rule.refuse(inside('a b.v')),
        isNull,
        reason: 'white space inside a name is an ordinary name',
      );
    });

    test('a symlink inside a root that points outside is refused', () {
      if (Platform.isWindows) return;
      final target = File(outside('secret.v'))..writeAsStringSync('x');
      Link(inside('alias.v')).createSync(target.path);
      final rule = CxpPathContainment(roots: () => [openRoot.path]);
      expect(
        rule.refuse(inside('alias.v')),
        isNotNull,
        reason: 'the rule applies to the resolved file, not the spelling',
      );
    });

    test('a path that merely shares a prefix with a root is refused', () {
      final rule = CxpPathContainment(roots: () => [openRoot.path]);
      final sibling = '${openRoot.path}-not-really';
      Directory(sibling).createSync();
      expect(rule.refuse(p.join(sibling, 'a.v')), isNotNull);
    });

    test('the roots callback is consulted on every check', () {
      final roots = <String>[];
      final rule = CxpPathContainment(roots: () => roots);
      expect(
        rule.refuse(inside('a.v')),
        'no directory is open in this session',
      );
      roots.add(openRoot.path);
      expect(rule.refuse(inside('a.v')), isNull);
      roots
        ..clear()
        ..add(otherRoot.path);
      expect(
        rule.refuse(inside('a.v')),
        'file_path is outside the directories open in this session',
      );
    });

    test('reasons never repeat the path', () {
      final rule = CxpPathContainment(roots: () => [openRoot.path]);
      final probe = outside('attacker-chosen-name.v');
      expect(rule.refuse(probe), isNot(contains('attacker-chosen-name')));
      expect(
        const CxpPathContainment().refuse('rel/attacker.v'),
        isNot(contains('attacker')),
      );
    });

    test('roots that do not exist still contain lexically', () {
      final ghost = p.join(tempDir.path, 'not-created-yet');
      final rule = CxpPathContainment(roots: () => [ghost]);
      expect(rule.allows(p.join(ghost, 'a.v')), isTrue);
      expect(rule.allows(outside('a.v')), isFalse);
    });
  });

  // CXP §11.3: symlinks resolved, "with each `..` segment interpreted the way
  // the filesystem interprets it — after the symlink before it has been
  // followed, not by collapsing the two lexically". Creating a symlink needs a
  // privilege Windows runners do not grant, so the cases that make one run on
  // POSIX only.
  group('canonicalisation reads a path the way the filesystem does', () {
    late CxpPathContainment rule;

    setUp(() {
      rule = CxpPathContainment(roots: () => [openRoot.path]);
    });

    test(
      'a `..` after a directory symlink is judged from the link target',
      () {
        final deep = Directory(outside('deep'))..createSync();
        File(outside('secret.v')).writeAsStringSync('secret');
        Link(inside('dirlink')).createSync(deep.path);

        final bypass = p.join(openRoot.path, 'dirlink', '..', 'secret.v');
        // The filesystem follows `dirlink` and only then applies `..`, so this
        // spelling opens the file beside the link's target, outside the root.
        // Collapsing `dirlink/..` as text puts it inside.
        expect(File(bypass).readAsStringSync(), 'secret');
        expect(rule.refuse(bypass), isNotNull);
        expect(
          rule.refuse(p.join(openRoot.path, 'dirlink', '..', 'new.v')),
          isNotNull,
          reason: 'a file that does not exist yet, reached the same way',
        );
        expect(
          rule.refuse(p.join(openRoot.path, 'dirlink', '..', 'sub', 'b.v')),
          isNotNull,
          reason: 'and a directory that does not exist yet',
        );
      },
      skip: Platform.isWindows ? 'POSIX symlinks' : false,
    );

    test(
      'a `..` after a link whose target is inside the root is allowed',
      () {
        final ab = Directory(inside(p.join('a', 'b')))
          ..createSync(recursive: true);
        File(inside(p.join('a', 'x.v'))).writeAsStringSync('x');
        Link(inside('ab')).createSync(ab.path);
        expect(rule.allows(p.join(openRoot.path, 'ab', '..', 'x.v')), isTrue);
        expect(rule.allows(p.join(openRoot.path, 'ab', '..', 'y.v')), isTrue);
      },
      skip: Platform.isWindows ? 'POSIX symlinks' : false,
    );

    test(
      'a `..` in the part of a path that does not exist is refused',
      () {
        // No filesystem reading of these is inside: a directory that does not
        // exist cannot be walked out of, and one created later could be a link.
        expect(
          rule.refuse(
            p.join(openRoot.path, 'missing', '..', '..', 'other', 'a.v'),
          ),
          isNotNull,
        );
        expect(
          rule.refuse(p.join(openRoot.path, 'missing', '..', 'a.v')),
          isNotNull,
        );
      },
      skip: Platform.isWindows
          ? 'Windows collapses `..` as text before the filesystem sees it'
          : false,
    );

    test('a path that does not exist yet is judged by its deepest existing '
        'ancestor', () {
      expect(rule.allows(inside(p.join('new', 'dir', 'a.v'))), isTrue);
      if (Platform.isWindows) return;
      Link(inside('outlink')).createSync(otherRoot.path);
      expect(rule.refuse(inside(p.join('outlink', 'new', 'a.v'))), isNotNull);
    });

    test(
      'a root spelled through a symlink contains what its target contains',
      () {
        final rootLink = Link(p.join(tempDir.path, 'rootlink'))
          ..createSync(openRoot.path);
        final viaLink = CxpPathContainment(roots: () => [rootLink.path]);
        expect(viaLink.allows(inside('a.v')), isTrue);
        expect(viaLink.allows(p.join(rootLink.path, 'new', 'a.v')), isTrue);
        expect(viaLink.refuse(outside('a.v')), isNotNull);
        expect(rule.allows(p.join(rootLink.path, 'a.v')), isTrue);
      },
      skip: Platform.isWindows ? 'POSIX symlinks' : false,
    );

    test('either spelling of a linked system directory matches the other', () {
      // macOS: the temp directory is under `/var`, a link to `/private/var`.
      // A root and a path spelled on different sides of that link must still
      // compare as one tree, whether the path exists or not.
      File(inside('here.v')).writeAsStringSync('x');
      final resolved = openRoot.resolveSymbolicLinksSync();
      for (final rootSpelling in <String>[openRoot.path, resolved]) {
        final r = CxpPathContainment(roots: () => [rootSpelling]);
        for (final base in <String>[openRoot.path, resolved]) {
          final label = 'root $rootSpelling, path under $base';
          expect(r.allows(p.join(base, 'here.v')), isTrue, reason: label);
          expect(r.allows(p.join(base, 'new', 'a.v')), isTrue, reason: label);
          expect(r.allows(p.join(base, '..', 'other')), isFalse, reason: label);
        }
      }
    });

    test(
      'chains of links are followed to the end',
      () {
        File(outside('secret.v')).writeAsStringSync('s');
        Link(inside('l2')).createSync(otherRoot.path);
        Link(inside('l1')).createSync(inside('l2'));
        expect(rule.refuse(inside(p.join('l1', 'secret.v'))), isNotNull);
        expect(rule.refuse(inside(p.join('l1', 'new.v'))), isNotNull);
        expect(rule.refuse(inside(p.join('l1', '..', 'x.v'))), isNotNull);

        // A relative link target is read from the link's own directory.
        Link(inside('rel')).createSync(p.join('..', 'other'));
        expect(rule.refuse(inside(p.join('rel', 'secret.v'))), isNotNull);

        // A chain that ends back inside the root is inside.
        final real = Directory(inside('real'))..createSync();
        Link(inside('m2')).createSync(real.path);
        Link(inside('m1')).createSync(inside('m2'));
        expect(rule.allows(inside(p.join('m1', 'a.v'))), isTrue);
      },
      skip: Platform.isWindows ? 'POSIX symlinks' : false,
    );

    test(
      'a link that cannot be resolved is refused',
      () {
        // A dangling link names nothing yet; a write through it would create
        // the file wherever the link points.
        Link(inside('dangling')).createSync(outside('not-yet.v'));
        expect(rule.refuse(inside('dangling')), isNotNull);
        expect(rule.refuse(inside(p.join('dangling', 'a.v'))), isNotNull);
        Link(inside('loop')).createSync(inside('loop'));
        expect(rule.refuse(inside(p.join('loop', 'a.v'))), isNotNull);
      },
      skip: Platform.isWindows ? 'POSIX symlinks' : false,
    );
  });

  group('LocalCxpServer applies the rule before dispatch', () {
    late LocalCxpServer server;
    late LocalCxpClient client;
    late List<InboundCxpMessage> inbound;
    late List<CxpClientInbound> replies;

    setUp(() async {
      server = LocalCxpServer(
        selfIdentity: _serverId,
        containment: CxpPathContainment(roots: () => [openRoot.path]),
      );
      await server.start();
      addTearDown(server.stop);
      inbound = <InboundCxpMessage>[];
      server.inbound.listen(inbound.add);
      client = LocalCxpClient(selfIdentity: _peerId);
      addTearDown(client.dispose);
      replies = <CxpClientInbound>[];
      client.inbound.listen(replies.add);
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
      );
    });

    test(
      'a request_open_source outside the roots is acked honored: false '
      'with the reason and never reaches the product',
      () async {
        client.send(RequestOpenSource(filePath: outside('a.v'), line: 3));
        await pollUntil(
          () => replies.any((r) => r.message is RequestOpenSourceAck),
          reason: 'the refusal must be acknowledged',
        );
        final ack =
            replies.firstWhere((r) => r.message is RequestOpenSourceAck).message
                as RequestOpenSourceAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('outside'));
        expect(ack.reason, isNot(contains(otherRoot.path)));

        // A following inside request bounds the negative assertion.
        client.send(RequestOpenSource(filePath: inside('b.v'), line: 1));
        await pollUntil(
          () => inbound.any((m) => m.message is RequestOpenSource),
          reason: 'an inside request must dispatch',
        );
        final dispatched = inbound
            .map((m) => m.message)
            .whereType<RequestOpenSource>()
            .toList();
        expect(dispatched.map((m) => m.filePath), [inside('b.v')]);
      },
    );

    test(
      'a file_path with surrounding white space is refused, never '
      'dispatched as spelled',
      () async {
        final lenient = LocalCxpServer(selfIdentity: _serverId);
        await lenient.start();
        addTearDown(lenient.stop);
        final seen = <InboundCxpMessage>[];
        lenient.inbound.listen(seen.add);
        final c = LocalCxpClient(selfIdentity: _peerId);
        addTearDown(c.dispose);
        final acks = <CxpClientInbound>[];
        c.inbound.listen(acks.add);
        await c.connect(
          host: '127.0.0.1',
          port: lenient.boundPort!,
          token: lenient.authToken,
        );
        c.send(const RequestOpenSource(filePath: ' /etc/hosts', line: 1));
        await pollUntil(
          () => acks.any((r) => r.message is RequestOpenSourceAck),
          reason: 'the refusal must be acknowledged',
        );
        final ack = acks.single.message as RequestOpenSourceAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, isNot(contains('hosts')));

        // A following well-formed request bounds the negative assertion.
        c.send(RequestOpenSource(filePath: inside('a.v'), line: 1));
        await pollUntil(
          () => seen.any((m) => m.message is RequestOpenSource),
          reason: 'a well-formed request must dispatch',
        );
        expect(
          seen.map((m) => (m.message as RequestOpenSource).filePath),
          [inside('a.v')],
        );
      },
    );

    test('a relative file_path is refused even with roots', () async {
      client.send(const RequestOpenSource(filePath: 'a.v', line: 1));
      await pollUntil(
        () => replies.any((r) => r.message is RequestOpenSourceAck),
        reason: 'the refusal must be acknowledged',
      );
      final ack = replies.single.message as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('absolute'));
      expect(inbound, isEmpty);
    });

    test(
      'a request_open_artifact whose path hint is outside is dispatched '
      'with the hint removed; an inside hint is kept',
      () async {
        client
          ..send(
            RequestOpenArtifact(
              designId: 'd1',
              artifactKind: 'waveform',
              path: outside('w.vcd'),
            ),
          )
          ..send(
            RequestOpenArtifact(
              designId: 'd2',
              artifactKind: 'waveform',
              path: inside('w.vcd'),
            ),
          );
        await pollUntil(
          () =>
              inbound
                  .whereType<InboundCxpMessage>()
                  .where(
                    (m) => m.message is RequestOpenArtifact,
                  )
                  .length ==
              2,
          reason: 'both requests dispatch (the design_id may still resolve)',
        );
        final byDesign = {
          for (final m in inbound)
            if (m.message is RequestOpenArtifact)
              (m.message as RequestOpenArtifact).designId:
                  m.message as RequestOpenArtifact,
        };
        expect(byDesign['d1']!.path, isNull, reason: 'outside hint removed');
        expect(byDesign['d1']!.artifactKind, 'waveform');
        expect(byDesign['d2']!.path, inside('w.vcd'), reason: 'inside kept');
        // The envelope still carries what was on the wire.
        final d1Envelope = inbound
            .firstWhere(
              (m) => (m.message as RequestOpenArtifact).designId == 'd1',
            )
            .envelope;
        expect(d1Envelope.payload['path'], outside('w.vcd'));
        expect(replies, isEmpty, reason: 'no ack from the server itself');
      },
    );

    test('the default rule admits any absolute path', () async {
      final lenient = LocalCxpServer(selfIdentity: _serverId);
      await lenient.start();
      addTearDown(lenient.stop);
      final seen = <InboundCxpMessage>[];
      lenient.inbound.listen(seen.add);
      final c = LocalCxpClient(selfIdentity: _peerId);
      addTearDown(c.dispose);
      await c.connect(
        host: '127.0.0.1',
        port: lenient.boundPort!,
        token: lenient.authToken,
      );
      c.send(RequestOpenSource(filePath: outside('a.v'), line: 1));
      await pollUntil(
        () => seen.any((m) => m.message is RequestOpenSource),
        reason: 'the floor rule admits an absolute path',
      );
    });
  });

  group('the rule holds on the connector link too', () {
    test(
      'a refused request_open_source injected from a link is acked over '
      'the link and never dispatched',
      () async {
        final server = LocalCxpServer(
          selfIdentity: _serverId,
          containment: CxpPathContainment(roots: () => [openRoot.path]),
        );
        await server.start();
        addTearDown(server.stop);
        final inbound = <InboundCxpMessage>[];
        final sentOverLink = <CxpMessage>[];
        server
          ..inbound.listen(inbound.add)
          ..attachLinkedPeer(_peerId, sentOverLink.add);

        // What CxpPeerConnector does for every frame a link receives.
        void arriveOverLink(String messageId, String filePath) {
          server.injectInbound(
            InboundCxpMessage(
              envelope: CxpEnvelope(
                messageId: messageId,
                from: _peerId.peerId,
                kind: CxpMessageKind.requestOpenSource,
                payload: const <String, Object?>{},
              ),
              message: RequestOpenSource(filePath: filePath, line: 1),
              from: _peerId,
            ),
          );
        }

        arriveOverLink('link-1', outside('a.v'));
        expect(inbound, isEmpty);
        expect(sentOverLink, hasLength(1));
        final ack = sentOverLink.single as RequestOpenSourceAck;
        expect(ack.inReplyTo, 'link-1');
        expect(ack.honored, isFalse);

        arriveOverLink('link-2', inside('a.v'));
        // The dispatch stream delivers asynchronously; the admitted request
        // arriving bounds the refused one's absence.
        await pollUntil(
          () => inbound.isNotEmpty,
          reason: 'an inside request over a link must dispatch',
        );
        expect(
          inbound.map((m) => (m.message as RequestOpenSource).filePath),
          [inside('a.v')],
        );
        expect(sentOverLink, hasLength(1), reason: 'no ack for an admitted');
      },
    );
  });

  group('CxpWorkspaceStore applies the rule to what it resolves', () {
    test(
      'an artifact outside the roots is persisted but never resolved',
      () async {
        final ws = p.join(tempDir.path, 'workspace');
        final producer = CxpWorkspaceStore(workspaceDirectory: ws);
        final consumer = CxpWorkspaceStore(
          workspaceDirectory: ws,
          containment: CxpPathContainment(roots: () => [openRoot.path]),
        );
        final insideFile = File(inside('in.vcd'))..writeAsStringSync('x');
        final outsideFile = File(outside('out.vcd'))..writeAsStringSync('x');
        // Recent, TTL-safe timestamps: the outside record is the newer one,
        // so without the rule it is what `resolveArtifact` would pick.
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await producer.upsertArtifact(
          designId: 'd',
          kind: 'waveform',
          path: outsideFile.path,
          producer: 'simcrux',
          ts: nowMs - 1000,
        );
        await producer.upsertArtifact(
          designId: 'd',
          kind: 'waveform',
          path: insideFile.path,
          producer: 'simcrux',
          ts: nowMs - 2000,
        );

        expect(producer.readArtifacts('d'), hasLength(2));
        expect(
          consumer.readArtifacts('d').map((a) => a.path),
          [insideFile.path],
        );
        // Without the rule the newest (outside) entry would win.
        expect(
          producer.resolveArtifact('d', 'waveform')!.path,
          outsideFile.path,
        );
        expect(
          consumer.resolveArtifact('d', 'waveform')!.path,
          insideFile.path,
        );

        // The consumer's own upsert does not drop the outside record.
        await consumer.upsertArtifact(
          designId: 'd',
          kind: 'source',
          path: insideFile.path,
          producer: 'netcrux',
        );
        expect(producer.readArtifacts('d'), hasLength(3));
        expect(consumer.readArtifacts('d'), hasLength(2));
      },
    );
  });
}
