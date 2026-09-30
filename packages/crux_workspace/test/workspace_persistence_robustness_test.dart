// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Persistence robustness.
///
/// Companion to `workspace_service_test.dart` (which covers the happy paths
/// and the quarantine discipline). This file covers the two failure modes that
/// suite audit flagged as data-losing:
///
/// * concurrent saves racing on a shared temp path, and
/// * a decode `TypeError` slipping past every recovery handler and bricking
///   launch permanently.

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'value': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['value'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

/// A codec whose payload decode throws a `TypeError` — the shape a product's
/// own codec takes when the on-disk payload shape drifts. TypeError is an
/// Error, not an Exception, which is exactly why it used to escape.
class _CastingCodec extends WorkspaceCodec<String> {
  const _CastingCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'value': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['value']! as String;

  @override
  String displayNameFor(String p) => p;
}

Workspace<String> _workspaceWith(String payload) {
  final pane = WorkspacePane(id: PaneId.generate());
  final tab = WorkspaceTab<String>(
    id: TabId.generate(),
    displayName: payload,
    paneId: pane.id,
    payload: payload,
  );
  return Workspace<String>(
    tabs: [tab],
    panes: [pane.copyWith(activeTabId: tab.id)],
    activePaneId: pane.id,
  );
}

void main() {
  late Directory tempDir;
  final messages = <String>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_ws_robust_');
    messages.clear();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  WorkspaceService<String> makeService({WorkspaceCodec<String>? codec}) =>
      WorkspaceService<String>(
        codec: codec ?? const _StringCodec(),
        directoryFactory: () async => tempDir,
        logger: messages.add,
      );

  group('concurrent saves must not race', () {
    test(
      'overlapping saves all land, and the last one wins on disk',
      () async {
        final service = makeService();

        // Fire many saves without awaiting: this is the quit-during-debounce
        // shape, where a flush starts a write while the debounced one runs.
        final futures = [
          for (var i = 0; i < 25; i++) service.save(_workspaceWith('p$i')),
        ];
        await Future.wait(futures);

        final file = File('${tempDir.path}/workspace.json');
        expect(file.existsSync(), isTrue);

        // The document must be complete and parseable — an interleaved write
        // would produce truncated or doubled JSON.
        final decoded = jsonDecode(await file.readAsString());
        expect(decoded, isA<Map<String, Object?>>());
        final reloaded = await service.load();
        expect(
          reloaded.tabs.single.payload,
          'p24',
          reason:
              'saves are serialized, so the last one issued is the one '
              'left on disk',
        );
        expect(
          messages.where((m) => m.contains('save failed')),
          isEmpty,
          reason: 'a lost save shows up as a swallowed ENOENT on the temp path',
        );
      },
    );

    test('no temp siblings survive a burst of saves', () async {
      final service = makeService();
      await Future.wait([
        for (var i = 0; i < 10; i++) service.save(_workspaceWith('p$i')),
      ]);

      final strays = tempDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.tmp'))
          .toList();
      expect(
        strays,
        isEmpty,
        reason: 'each write renames its own unique temp sibling away',
      );
    });

    test('each save writes a distinct temp path', () async {
      // Two services over the same directory model two windows / two
      // processes — outside any single instance's serialization, so the temp
      // name itself has to be unique, not just the ordering.
      final a = makeService();
      final b = makeService();
      await Future.wait([
        a.save(_workspaceWith('from-a')),
        b.save(_workspaceWith('from-b')),
      ]);

      final loaded = await a.load();
      expect(loaded.tabs, hasLength(1));
      expect(loaded.tabs.single.payload, anyOf('from-a', 'from-b'));
      expect(messages.where((m) => m.contains('save failed')), isEmpty);
    });

    test(
      'clear() sweeps a stale temp sibling left by a crashed write',
      () async {
        final stray = File('${tempDir.path}/workspace.json.999-0.tmp')
          ..writeAsStringSync('{}');
        final legacy = File('${tempDir.path}/workspace.json.tmp')
          ..writeAsStringSync('{}');
        final service = makeService();
        await service.save(_workspaceWith('p'));

        await service.clear();

        expect(stray.existsSync(), isFalse);
        expect(legacy.existsSync(), isFalse);
        expect(File('${tempDir.path}/workspace.json').existsSync(), isFalse);
      },
    );

    test(
      'WorkspaceNotifier serializes its own saves and flush awaits them all',
      () async {
        final service = makeService();
        final provider =
            AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
              () => WorkspaceNotifier<String>(
                service: service,
                autoSaveDebounce: Duration.zero,
              ),
            );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(provider.future);
        final notifier = container.read(provider.notifier);

        for (var i = 0; i < 12; i++) {
          await notifier.openTab(displayName: 'tab$i', payload: 'p$i');
        }
        // The contract: after flushPendingSave returns, the on-disk document
        // matches memory. Previously this could return while an earlier save
        // was still running and about to overwrite with a stale payload.
        await notifier.flushPendingSave();

        final onDisk = await service.load();
        expect(onDisk.tabs, hasLength(12));
        expect(onDisk.tabs.last.displayName, 'tab11');
      },
    );
  });

  group('a decode Error must be quarantined, not thrown', () {
    Future<void> writeRaw(String json) =>
        File('${tempDir.path}/workspace.json').writeAsString(json);

    test(
      'a string "version" is quarantined instead of bricking every launch',
      () async {
        // The canonical case: `"version": "1"` where an int is expected. The
        // old `as num?` cast raised a TypeError, which is an Error and so
        // matched none of the handlers — it escaped load() and crashed boot,
        // on every subsequent launch, forever.
        await writeRaw('{"version": "1", "panes": [], "activePaneId": "p"}');
        final service = makeService();

        final ws = await service.load();

        expect(ws.isEmpty, isTrue);
        final recovery = service.takeRecovery();
        expect(recovery, isNotNull, reason: 'the document must be quarantined');
        expect(File(recovery!.quarantinePath).existsSync(), isTrue);
        expect(
          File('${tempDir.path}/workspace.json').existsSync(),
          isFalse,
          reason: 'the bad document is moved aside so the next launch is clean',
        );
      },
    );

    test('a second launch after quarantine loads cleanly', () async {
      await writeRaw('{"version": "1", "panes": [], "activePaneId": "p"}');
      final service = makeService();
      await service.load();

      // This is the whole point of quarantine: launch N+1 must work.
      final second = await service.load();
      expect(second.isEmpty, isTrue);
      expect(second.panes, hasLength(1));
    });

    for (final (label, raw) in <(String, String)>[
      (
        'non-string pane id',
        '{"version":1,"panes":[{"id":7}],'
            '"activePaneId":"p"}',
      ),
      (
        'non-string activePaneId',
        '{"version":1,'
            '"panes":[{"id":"p"}],"activePaneId":42}',
      ),
      (
        'non-string activeTabId',
        '{"version":1,'
            '"panes":[{"id":"p","activeTabId":5}],"activePaneId":"p"}',
      ),
      (
        'non-string tab id',
        '{"version":1,"panes":[{"id":"p"}],'
            '"activePaneId":"p","tabs":[{"id":9,"paneId":"p"}]}',
      ),
      (
        'non-string tab paneId',
        '{"version":1,"panes":[{"id":"p"}],'
            '"activePaneId":"p","tabs":[{"id":"t","paneId":true}]}',
      ),
    ]) {
      test('$label is quarantined, not thrown', () async {
        await writeRaw(raw);
        final service = makeService();

        final ws = await service.load();

        expect(ws.isEmpty, isTrue);
        expect(
          service.takeRecovery(),
          isNotNull,
          reason: '$label must reach the quarantine path',
        );
      });
    }

    test(
      'a TypeError raised by the product codec is quarantined too',
      () async {
        // The codec is product code; it can throw an Error the package has no
        // way to anticipate. That must still degrade, not brick.
        await writeRaw(
          '{"version":1,"panes":[{"id":"p"}],"activePaneId":"p",'
          '"tabs":[{"id":"t","paneId":"p","value":123}]}',
        );
        final service = makeService(codec: const _CastingCodec());

        final ws = await service.load();

        expect(ws.isEmpty, isTrue);
        expect(service.takeRecovery(), isNotNull);
      },
    );

    test(
      'loadFromPath throws on a decode Error without quarantining',
      () async {
        // Regression: loadFromPath used to return Workspace.empty() on any
        // failure, which lets the notifier evict the live session's scopes and
        // then auto-save the empty document over the managed workspace.json —
        // silent destruction of a good session. It must surface the failure
        // instead, and still never move the user-chosen file aside.
        final path = '${tempDir.path}/named.json';
        await File(path).writeAsString(
          '{"version":1,"panes":[{"id":"p"}],"activePaneId":"p",'
          '"tabs":[{"id":"t","paneId":"p","value":123}]}',
        );
        final service = makeService(codec: const _CastingCodec());

        await expectLater(
          service.loadFromPath(path),
          throwsA(
            isA<WorkspaceLoadException>().having(
              (e) => e.path,
              'path',
              path,
            ),
          ),
        );
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'a user-chosen document is never moved aside',
        );
        expect(service.takeRecovery(), isNull);
      },
    );

    test('loadFromPath throws on a missing file', () async {
      final service = makeService();
      await expectLater(
        service.loadFromPath('${tempDir.path}/absent.json'),
        throwsA(isA<WorkspaceLoadException>()),
      );
    });

    test('loadFromPath throws on malformed JSON', () async {
      final path = '${tempDir.path}/bad.json';
      await File(path).writeAsString('{not json');
      final service = makeService();
      await expectLater(
        service.loadFromPath(path),
        throwsA(isA<WorkspaceLoadException>()),
      );
      expect(File(path).existsSync(), isTrue);
    });

    test(
      'a well-formed document still loads — the guards did not over-reject',
      () async {
        final service = makeService();
        await service.save(_workspaceWith('keep-me'));
        final ws = await service.load();
        expect(ws.tabs.single.payload, 'keep-me');
        expect(service.takeRecovery(), isNull);
      },
    );

    test('a missing displayName still falls back to the codec', () async {
      await writeRaw(
        '{"version":1,"panes":[{"id":"p"}],"activePaneId":"p",'
        '"tabs":[{"id":"t","paneId":"p","value":"from-codec"}]}',
      );
      final service = makeService();
      final ws = await service.load();
      expect(ws.tabs.single.displayName, 'from-codec');
    });
  });
}
