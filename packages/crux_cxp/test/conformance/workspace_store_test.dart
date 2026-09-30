// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Shared-workspace artifact link store: upsert idempotency, resolution
/// (exact design_id+kind, with topModule/basename fallback), and stale
/// pruning by missing file / TTL.
void main() {
  late Directory tempDir;
  late Directory wsDir;
  late CxpWorkspaceStore store;

  /// Creates a real file so existence-based pruning keeps the entry.
  String touch(String name) {
    final f = File(p.join(tempDir.path, name))..writeAsStringSync('x');
    return f.path;
  }

  // Recent, TTL-safe timestamps whose relative order is well-defined.
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  int older() => nowMs - 2000;
  int newer() => nowMs - 1000;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_cxp_ws_');
    wsDir = Directory(p.join(tempDir.path, 'workspace'));
    store = CxpWorkspaceStore(workspaceDirectory: wsDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('sharedCxpWorkspaceDirectory', () {
    test('is the "workspace" sibling of the peers directory', () {
      final env = <String, String>{'HOME': '/home/u'};
      final peers = sharedCxpManifestDirectory(
        environment: env,
        operatingSystem: 'macos',
      );
      final ws = sharedCxpWorkspaceDirectory(
        environment: env,
        operatingSystem: 'macos',
      );
      expect(p.dirname(ws), p.dirname(peers));
      expect(p.basename(ws), 'workspace');
      expect(p.basename(peers), 'peers');
    });
  });

  group('upsertArtifact', () {
    test('records an artifact and reads it back', () async {
      final path = touch('cdc_capture.vcd');
      await store.upsertArtifact(
        designId: 'designs/cdc_capture',
        kind: 'waveform',
        path: path,
        producer: 'simcrux',
        topModule: 'tb_cdc_capture',
        basename: 'cdc_capture.vcd',
      );
      final read = store.readArtifacts('designs/cdc_capture');
      expect(read, hasLength(1));
      expect(read.single.kind, 'waveform');
      expect(read.single.producer, 'simcrux');
      expect(read.single.topModule, 'tb_cdc_capture');
      // Persisted on disk under <design_id>.json.
      expect(
        File(p.join(wsDir.path, 'designs/cdc_capture.json')).existsSync(),
        isTrue,
      );
    });

    test('is idempotent on (path, kind) and refreshes ts', () async {
      final path = touch('w.vcd');
      final first = await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: path,
        producer: 'simcrux',
        ts: 1000,
      );
      expect(first, hasLength(1));
      final second = await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: path,
        producer: 'simcrux',
        ts: 2000,
      );
      expect(second, hasLength(1), reason: 'same (path, kind) must not append');
      expect(second.single.ts, 2000, reason: 'ts must refresh');
    });

    test('different kinds at the same path are distinct entries', () async {
      final path = touch('design.v');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'source',
        path: path,
        producer: 'netcrux',
      );
      await store.upsertArtifact(
        designId: 'd',
        kind: 'netlist',
        path: path,
        producer: 'netcrux',
      );
      expect(store.readArtifacts('d'), hasLength(2));
    });
  });

  group('resolveArtifact', () {
    test('returns the sole artifact of the requested kind', () async {
      final path = touch('cdc.vcd');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: path,
        producer: 'simcrux',
      );
      final r = store.resolveArtifact('d', 'waveform');
      expect(r, isNotNull);
      expect(r!.path, path);
    });

    test('returns null when no artifact of the kind exists', () async {
      final path = touch('a.v');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'source',
        path: path,
        producer: 'netcrux',
      );
      expect(store.resolveArtifact('d', 'waveform'), isNull);
    });

    test('falls back to topModule among multiple of a kind', () async {
      final a = touch('a.vcd');
      final b = touch('b.vcd');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: a,
        producer: 'simcrux',
        topModule: 'tb_a',
        ts: older(),
      );
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: b,
        producer: 'simcrux',
        topModule: 'tb_b',
        ts: newer(),
      );
      final r = store.resolveArtifact('d', 'waveform', topModule: 'tb_a');
      expect(r!.path, a, reason: 'topModule must win over the newer entry');
    });

    test('falls back to basename leaf among multiple of a kind', () async {
      final a = touch('alpha.vcd');
      final b = touch('beta.vcd');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: a,
        producer: 'simcrux',
        ts: older(),
      );
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: b,
        producer: 'simcrux',
        ts: newer(),
      );
      // Pass a full path as the basename hint — matched by its leaf.
      final r = store.resolveArtifact(
        'd',
        'waveform',
        basename: '/some/other/alpha.vcd',
      );
      expect(r!.path, a);
    });

    test('falls back to newest ts when nothing else disambiguates', () async {
      final a = touch('a.vcd');
      final b = touch('b.vcd');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: a,
        producer: 'simcrux',
        ts: older(),
      );
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: b,
        producer: 'simcrux',
        ts: newer(),
      );
      expect(store.resolveArtifact('d', 'waveform')!.path, b);
    });
  });

  group('stale pruning', () {
    test('drops an entry whose file no longer exists', () async {
      final gone = touch('gone.vcd');
      final kept = touch('kept.vcd');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: gone,
        producer: 'simcrux',
      );
      await store.upsertArtifact(
        designId: 'd',
        kind: 'source',
        path: kept,
        producer: 'netcrux',
      );
      File(gone).deleteSync();

      final read = store.readArtifacts('d');
      expect(read, hasLength(1));
      expect(read.single.path, kept);
      // pruneDesign persists the pruned set so the dead entry does not linger.
      final surviving = await store.pruneDesign('d');
      expect(surviving, hasLength(1));
      expect(store.readArtifacts('d'), hasLength(1));
    });

    test('drops an entry whose ts is older than the TTL', () async {
      store = CxpWorkspaceStore(
        workspaceDirectory: wsDir.path,
        ttl: const Duration(minutes: 1),
      );
      final path = touch('old.vcd');
      final longAgo = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: path,
        producer: 'simcrux',
        ts: longAgo,
      );
      expect(store.readArtifacts('d'), isEmpty);
    });

    test('removes the design document once it empties', () async {
      final path = touch('only.vcd');
      await store.upsertArtifact(
        designId: 'd',
        kind: 'waveform',
        path: path,
        producer: 'simcrux',
      );
      final doc = File(p.join(wsDir.path, 'd.json'));
      expect(doc.existsSync(), isTrue);
      File(path).deleteSync();
      await store.pruneDesign('d'); // persists prune → empties → deletes doc
      expect(doc.existsSync(), isFalse);
    });
  });

  test('an unknown design reads empty', () {
    expect(store.readArtifacts('nope'), isEmpty);
    expect(store.resolveArtifact('nope', 'waveform'), isNull);
  });

  // A `design_id` is opaque on the wire and arrives from a peer on every
  // request_open_artifact. The one thing the store does with it is turn it
  // into a file name, and `p.join` was doing that unsafely: a `..` segment
  // walked out of the workspace, and an absolute id made `p.join` drop the
  // workspace directory altogether (measured: `/tmp/evil` -> `/tmp/evil.json`).
  group('design_id containment', () {
    /// Ids that must never name a file outside the workspace directory.
    /// [escapeAbsolute] is absolute and inside the test's temp root, so the
    /// negative assertion can look for the file it would have created.
    late String escapeAbsolute;

    setUp(() {
      escapeAbsolute = p.join(tempDir.path, 'escape-abs');
    });

    List<String> hostile() => <String>[
      '../escape-rel',
      '../../escape-rel2',
      'sub/../../escape-rel3',
      escapeAbsolute,
      '',
      'nul byte',
    ];

    test('isValidDesignId refuses every escape and accepts real ids', () {
      for (final id in hostile()) {
        expect(store.isValidDesignId(id), isFalse, reason: '"$id"');
      }
      for (final id in <String>[
        'd',
        cxpDesignIdForPath(tempDir.path),
        'designs/cdc_capture', // one level down, as the store has always allowed
        '..hidden', // a leading dot pair is a name, not a parent reference
        'a..b',
      ]) {
        expect(store.isValidDesignId(id), isTrue, reason: '"$id"');
      }
    });

    test('reads of a hostile id are empty', () {
      for (final id in hostile()) {
        expect(store.readArtifacts(id), isEmpty, reason: '"$id"');
        expect(store.resolveArtifact(id, 'waveform'), isNull, reason: '"$id"');
      }
    });

    test('an upsert with a hostile id writes nothing anywhere', () async {
      final path = touch('w.vcd');
      for (final id in hostile()) {
        final result = await store.upsertArtifact(
          designId: id,
          kind: 'waveform',
          path: path,
          producer: 'simcrux',
        );
        expect(result, isEmpty, reason: '"$id"');
      }
      // Nothing escaped: the temp root holds only the touched artifact — the
      // store did not even create its workspace directory, since it had
      // nothing to write into it.
      expect(File('$escapeAbsolute.json').existsSync(), isFalse);
      final rootEntries = tempDir
          .listSync()
          .map((e) => p.basename(e.path))
          .toSet();
      expect(rootEntries, {'w.vcd'});
      expect(wsDir.existsSync(), isFalse);
      // And the parent of the temp root gained no `escape-rel*.json`.
      final parent = Directory(p.dirname(tempDir.path));
      expect(
        parent.listSync().where(
          (e) => p.basename(e.path).startsWith('escape-rel'),
        ),
        isEmpty,
      );
    });

    test('pruneDesign of a hostile id is a no-op', () async {
      for (final id in hostile()) {
        expect(await store.pruneDesign(id), isEmpty, reason: '"$id"');
      }
    });
  });

  group('concurrent writers in one isolate', () {
    // A producer that publishes an artifact per finished test does so
    // concurrently. Each upsert used to read the design's document before any
    // of the others had written it, so the last rename kept only its own
    // entry, and a peer's request_open_artifact resolved to the wrong file.
    const designId = 'designs/regression';
    const concurrent = 24;

    test('every one of $concurrent concurrent upserts for one design '
        'survives', () async {
      final paths = [for (var i = 0; i < concurrent; i++) touch('t$i.vcd')];
      final returned = await Future.wait([
        for (final path in paths)
          store.upsertArtifact(
            designId: designId,
            kind: 'waveform',
            path: path,
            producer: 'simcrux',
          ),
      ]);
      expect(
        store.readArtifacts(designId).map((a) => a.path).toSet(),
        paths.toSet(),
      );
      // Each call saw every upsert queued before it.
      expect(returned.map((r) => r.length), [
        for (var i = 1; i <= concurrent; i++) i,
      ]);
    });

    test('two stores on the same directory share the queue', () async {
      // Products rebuild the store when the containment rule changes, so an
      // old instance's write can still be in flight when a new one upserts.
      final other = CxpWorkspaceStore(workspaceDirectory: wsDir.path);
      final paths = [for (var i = 0; i < concurrent; i++) touch('s$i.vcd')];
      await Future.wait([
        for (var i = 0; i < concurrent; i++)
          (i.isEven ? store : other).upsertArtifact(
            designId: designId,
            kind: 'waveform',
            path: paths[i],
            producer: 'simcrux',
          ),
      ]);
      expect(
        store.readArtifacts(designId).map((a) => a.path).toSet(),
        paths.toSet(),
      );
    });

    test('a prune queued among upserts drops only what is stale', () async {
      final stale = touch('stale.vcd');
      await store.upsertArtifact(
        designId: designId,
        kind: 'waveform',
        path: stale,
        producer: 'simcrux',
      );
      File(stale).deleteSync();
      final paths = [for (var i = 0; i < concurrent; i++) touch('p$i.vcd')];
      await Future.wait([
        for (var i = 0; i < concurrent; i++) ...[
          store.upsertArtifact(
            designId: designId,
            kind: 'waveform',
            path: paths[i],
            producer: 'simcrux',
          ),
          if (i == concurrent ~/ 2) store.pruneDesign(designId),
        ],
      ]);
      expect(
        store.readArtifacts(designId).map((a) => a.path).toSet(),
        paths.toSet(),
      );
    });

    test('a write that fails fails its own call, and the calls queued '
        'behind it still run', () async {
      // A directory where the design's document belongs: the rename that
      // would replace it fails, every time.
      Directory(p.join(wsDir.path, '$designId.json')).createSync(
        recursive: true,
      );
      final calls = [
        for (var i = 0; i < 3; i++)
          store
              .upsertArtifact(
                designId: designId,
                kind: 'waveform',
                path: touch('f$i.vcd'),
                producer: 'simcrux',
              )
              .then<Object?>((r) => r, onError: (Object e) => e),
      ];
      final outcomes = await Future.wait(
        calls,
      ).timeout(const Duration(seconds: 5));
      expect(outcomes, everyElement(isA<FileSystemException>()));
    });
  });
}
