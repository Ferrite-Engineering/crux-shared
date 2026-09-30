// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp/src/cxp_private_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _identity = PeerIdentity(
  peerId: 'wavecrux-perm-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

/// CXP §10.1–10.2: since 1.2 the manifest directory holds every local
/// peer's token, and presenting a token proves file access only if other
/// users cannot read it. So a peer creates each directory it creates on the
/// manifest path owner-only (`0700`), and writes the manifest owner-only
/// (`0600`) rather than relying on a directory above it. A Linux home that
/// is `0755` is the case this closes: there the default modes let every
/// local user read every peer's token.
///
/// The mode cases run on POSIX only: Windows has an access-control list,
/// not a mode, and the per-user profile's list is what keeps `%APPDATA%`
/// private.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_cxp_perm_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  String modeOf(String path) =>
      (FileStat.statSync(path).mode & 0x1ff).toRadixString(8).padLeft(3, '0');

  Future<void> chmod(String mode, String path) async {
    final r = await Process.run('chmod', [mode, path]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
  }

  String manifestIn(String dir) => p.join(dir, '${_identity.peerId}.json');

  const posixOnly = 'POSIX modes; Windows relies on the profile ACL';

  test(
    'the writer creates each directory it creates owner-only, leaves the '
    'ones it found alone, and writes the manifest owner-only',
    () async {
      final base = Directory(p.join(tempDir.path, 'share'))..createSync();
      await chmod('755', base.path);
      final dir = p.join(base.path, 'crux', 'cxp', 'peers');

      final writer = CxpManifestWriter(
        manifestDirectory: dir,
        heartbeatInterval: null,
      );
      addTearDown(writer.remove);
      await writer.write(identity: _identity, host: '127.0.0.1', port: 54322);

      expect(modeOf(base.path), '755', reason: 'not created here');
      for (final created in <String>[
        p.join(base.path, 'crux'),
        p.join(base.path, 'crux', 'cxp'),
        dir,
      ]) {
        expect(modeOf(created), '700', reason: created);
      }
      expect(modeOf(manifestIn(dir)), '600');
      expect(
        File(manifestIn(dir)).readAsStringSync(),
        contains(writer.authToken),
        reason: 'the file that is private is the one holding the token',
      );
    },
    skip: Platform.isWindows ? posixOnly : false,
  );

  test(
    'an existing manifest directory with a looser mode is tightened',
    () async {
      final dir = Directory(p.join(tempDir.path, 'peers'))..createSync();
      await chmod('755', dir.path);
      final writer = CxpManifestWriter(
        manifestDirectory: dir.path,
        heartbeatInterval: null,
      );
      addTearDown(writer.remove);
      await writer.write(identity: _identity, host: '127.0.0.1', port: 54322);
      expect(modeOf(dir.path), '700');
      expect(modeOf(manifestIn(dir.path)), '600');
    },
    skip: Platform.isWindows ? posixOnly : false,
  );

  test(
    'every heartbeat rewrite is owner-only too, and leaves no temporary '
    'file behind',
    () async {
      final dir = p.join(tempDir.path, 'peers');
      final writer = CxpManifestWriter(
        manifestDirectory: dir,
        heartbeatInterval: const Duration(milliseconds: 20),
      );
      addTearDown(writer.remove);
      await writer.write(identity: _identity, host: '127.0.0.1', port: 54322);
      final first = File(manifestIn(dir)).readAsStringSync();
      await pollUntil(
        () => File(manifestIn(dir)).readAsStringSync() != first,
        reason: 'the heartbeat must rewrite the manifest',
      );
      expect(modeOf(manifestIn(dir)), '600');
      await writer.remove();
      expect(Directory(dir).listSync(), isEmpty);
    },
    skip: Platform.isWindows ? posixOnly : false,
  );

  test(
    'discovery creates the directory owner-only as well',
    () async {
      final dir = p.join(tempDir.path, 'fresh', 'peers');
      final discovery = CxpDiscovery(manifestDirectory: dir);
      addTearDown(discovery.stop);
      await discovery.start();
      expect(modeOf(p.join(tempDir.path, 'fresh')), '700');
      expect(modeOf(dir), '700');
    },
    skip: Platform.isWindows ? posixOnly : false,
  );

  test(
    'the scratch file is owner-only before the token is written into it',
    () async {
      final dest = File(p.join(tempDir.path, 'm.json'));
      final seen = <String>[];
      await writeCxpPrivateFileAtomic(
        dest,
        'the-token',
        onBeforeWrite: (scratch) => seen.add(
          'before write: ${modeOf(scratch.path)} '
          '"${scratch.readAsStringSync()}"',
        ),
        onBeforeRename: (scratch) => seen.add(
          'before rename: ${modeOf(scratch.path)} '
          '"${scratch.readAsStringSync()}"',
        ),
      );
      expect(seen, [
        'before write: 600 ""',
        'before rename: 600 "the-token"',
      ]);
      expect(modeOf(dest.path), '600');
    },
    skip: Platform.isWindows ? posixOnly : false,
  );

  test('a failed write leaves the destination as it was, and no scratch '
      'file', () async {
    final dest = File(p.join(tempDir.path, 'm.json'))..writeAsStringSync('old');
    await expectLater(
      writeCxpPrivateFileAtomic(
        dest,
        'new',
        onBeforeRename: (_) => throw StateError('interrupted'),
      ),
      throwsStateError,
    );
    expect(dest.readAsStringSync(), 'old');
    expect(tempDir.listSync().map((e) => p.basename(e.path)), ['m.json']);
  });
}
