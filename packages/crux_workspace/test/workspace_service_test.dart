// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _StringPayloadCodec extends WorkspaceCodec<String> {
  const _StringPayloadCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String payload) => {'value': payload};

  @override
  String payloadFromJson(Map<String, Object?> json) =>
      json['value'] as String? ?? '';

  @override
  String displayNameFor(String payload) => payload;
}

void main() {
  group('WorkspaceService<String>', () {
    late Directory tempDir;
    late WorkspaceService<String> service;
    final messages = <String>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('crux_workspace_test_');
      messages.clear();
      service = WorkspaceService<String>(
        codec: const _StringPayloadCodec(),
        directoryFactory: () async => tempDir,
        logger: messages.add,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('load() of a missing file returns Workspace.empty()', () async {
      final ws = await service.load();
      expect(ws.isEmpty, isTrue);
      expect(messages, isEmpty);
    });

    test('save() then load() round-trips', () async {
      final pane = WorkspacePane(id: PaneId.generate());
      final tab = WorkspaceTab(
        id: TabId.generate(),
        displayName: 'hi',
        paneId: pane.id,
        payload: 'payload-data',
      );
      final ws = Workspace<String>(
        tabs: [tab],
        panes: [pane.copyWith(activeTabId: tab.id)],
        activePaneId: pane.id,
      );
      await service.save(ws);
      final restored = await service.load();
      expect(restored, equals(ws));
      expect(restored.tabs.single.payload, equals('payload-data'));
    });

    test('save() writes atomically — no .tmp file remains', () async {
      await service.save(Workspace<String>.empty());
      final tempFile = File(p.join(tempDir.path, 'workspace.json.tmp'));
      final destFile = File(p.join(tempDir.path, 'workspace.json'));
      expect(tempFile.existsSync(), isFalse);
      expect(destFile.existsSync(), isTrue);
    });

    test(
      'an interrupted write (orphan .tmp) never clobbers the good document',
      () async {
        // Save a good document, then simulate a crash mid-write by leaving a
        // half-written temp sibling that was never renamed. The atomic
        // temp+rename contract means the live document is untouched and a
        // subsequent load still returns the good payload. (Mutation check:
        // a non-atomic `writeAsString` straight to `workspace.json` would
        // instead corrupt the live document here.)
        final pane = WorkspacePane(id: PaneId.generate());
        final tab = WorkspaceTab(
          id: TabId.generate(),
          displayName: 'good',
          paneId: pane.id,
          payload: 'good-payload',
        );
        final good = Workspace<String>(
          tabs: [tab],
          panes: [pane.copyWith(activeTabId: tab.id)],
          activePaneId: pane.id,
        );
        await service.save(good);
        File(
          p.join(tempDir.path, 'workspace.json.tmp'),
        ).writeAsStringSync('{ half-written gar');
        final restored = await service.load();
        expect(restored.tabs.single.payload, 'good-payload');
        // The orphan temp is not a corruption candidate — no quarantine.
        expect(service.takeRecovery(), isNull);
      },
    );

    // Returns the single `workspace.json.corrupt-*` quarantine file in the
    // temp dir, or null if none was written.
    File? quarantineFile() {
      const prefix = 'workspace.json.corrupt-';
      final matches = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith(prefix))
          .toList();
      return matches.isEmpty ? null : matches.single;
    }

    test('load() of invalid JSON quarantines + recovers to empty', () async {
      final file = File(p.join(tempDir.path, 'workspace.json'));
      await file.writeAsString('this is not json');
      final restored = await service.load();
      expect(restored.isEmpty, isTrue);
      expect(messages.length, greaterThan(0));
      // The corrupt file is moved aside, not left in place nor deleted.
      expect(file.existsSync(), isFalse);
      final quarantined = quarantineFile();
      expect(quarantined, isNotNull);
      expect(quarantined!.readAsStringSync(), 'this is not json');
      // The recovery record is exposed once, then cleared.
      final recovery = service.takeRecovery();
      expect(recovery, isNotNull);
      expect(recovery!.quarantinePath, quarantined.path);
      expect(service.takeRecovery(), isNull);
    });

    test('load() of a non-object root quarantines + recovers', () async {
      final file = File(p.join(tempDir.path, 'workspace.json'));
      await file.writeAsString('[1, 2, 3]');
      final restored = await service.load();
      expect(restored.isEmpty, isTrue);
      expect(file.existsSync(), isFalse);
      expect(quarantineFile(), isNotNull);
      expect(service.takeRecovery(), isNotNull);
    });

    test('load() of unknown schema version quarantines + recovers', () async {
      final file = File(p.join(tempDir.path, 'workspace.json'));
      await file.writeAsString(
        jsonEncode({
          'version': 99,
          'panes': [
            {'id': '11111111-1111-1111-1111-111111111111'},
          ],
          'activePaneId': '11111111-1111-1111-1111-111111111111',
        }),
      );
      final restored = await service.load();
      expect(restored.isEmpty, isTrue);
      expect(messages.length, greaterThan(0));
      expect(file.existsSync(), isFalse);
      expect(quarantineFile(), isNotNull);
      expect(service.takeRecovery(), isNotNull);
    });

    test('load() of a missing file records no recovery', () async {
      await service.load();
      expect(service.takeRecovery(), isNull);
      expect(quarantineFile(), isNull);
    });

    test('clear() removes the document', () async {
      await service.save(Workspace<String>.empty());
      await service.clear();
      final file = File(p.join(tempDir.path, 'workspace.json'));
      expect(file.existsSync(), isFalse);
    });

    test(
      'saveToPath() then loadFromPath() round-trips arbitrary path',
      () async {
        final named = p.join(tempDir.path, 'my.crux-workspace');
        final pane = WorkspacePane(id: PaneId.generate());
        final tab = WorkspaceTab(
          id: TabId.generate(),
          displayName: 'sample',
          paneId: pane.id,
          payload: 'p',
        );
        final original = Workspace<String>(
          tabs: [tab],
          panes: [pane.copyWith(activeTabId: tab.id)],
          activePaneId: pane.id,
        );
        await service.saveToPath(named, original);
        final restored = await service.loadFromPath(named);
        expect(restored, equals(original));
      },
    );

    test('sidecarPathFor returns a deterministic per-tab path', () async {
      final p1 = await service.sidecarPathFor('tab-a');
      final p2 = await service.sidecarPathFor('tab-a');
      expect(p1, equals(p2));
      expect(p1, isNotNull);
      expect(p1, endsWith('tab-a.json'));
    });

    test('deleteSidecar() is best-effort and survives missing file', () async {
      await service.deleteSidecar('does-not-exist');
      expect(messages, isEmpty);
    });

    test('clearAllSidecars() removes every per-tab sidecar', () async {
      // Materialize two sidecars under {dir}/sessions/.
      final pathA = await service.sidecarPathFor('tab-a');
      final pathB = await service.sidecarPathFor('tab-b');
      File(pathA!).writeAsStringSync('{}');
      File(pathB!).writeAsStringSync('{}');
      final sessionsDir = Directory(p.join(tempDir.path, 'sessions'));
      expect(sessionsDir.existsSync(), isTrue);
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);

      await service.clearAllSidecars();

      expect(sessionsDir.existsSync(), isFalse);
      expect(File(pathA).existsSync(), isFalse);
      expect(File(pathB).existsSync(), isFalse);
    });

    test('clearAllSidecars() is a no-op when no sessions dir exists', () async {
      // sessionsDir was never created — must not throw or log.
      await service.clearAllSidecars();
      expect(messages, isEmpty);
    });
  });

  // Directory-resolution failure resilience. This is the regression guard for
  // the Flutter Web file-open hang: when the storage directory can't be
  // resolved, every public method must degrade to a no-op (load → empty,
  // save → nothing) and MUST NOT let the failure — or the diagnostic logging
  // of it — escape. On web the trigger is path_provider's
  // MissingPluginException; here we reproduce the same control flow with a
  // directoryFactory that throws. (The `kIsWeb` short-circuit and the
  // stderr-unavailable-on-web path in _log are compile-time false on the VM
  // and are covered by the web integration suite instead.)
  group('WorkspaceService directory-resolution failure', () {
    WorkspaceService<String> makeService({void Function(String)? logger}) =>
        WorkspaceService<String>(
          codec: const _StringPayloadCodec(),
          directoryFactory: () async =>
              throw const FileSystemException('no app-support dir'),
          logger: logger,
        );

    test('load() returns empty instead of throwing', () async {
      final messages = <String>[];
      final service = makeService(logger: messages.add);
      final ws = await service.load();
      expect(ws.isEmpty, isTrue);
      expect(messages, isNotEmpty); // failure was logged, not thrown
    });

    test('save() is a no-op instead of throwing', () async {
      final service = makeService(logger: (_) {});
      await expectLater(
        service.save(Workspace<String>.empty()),
        completes,
      );
    });

    test('sidecarPathFor() returns null instead of throwing', () async {
      final service = makeService(logger: (_) {});
      expect(await service.sidecarPathFor('tab-a'), isNull);
    });

    test('clearAllSidecars() is a no-op instead of throwing', () async {
      final service = makeService(logger: (_) {});
      await expectLater(service.clearAllSidecars(), completes);
    });

    test(
      'with no logger injected, a resolution failure still cannot escape — '
      '_log must be side-effect-only',
      () async {
        // No logger → _log takes its stderr fallback. The contract is that
        // _log never throws, so the surrounding recovery stays intact even
        // when the diagnostic sink is unavailable (the web failure mode).
        final service = makeService();
        await expectLater(service.load(), completion(isNotNull));
        await expectLater(service.save(Workspace<String>.empty()), completes);
      },
    );
  });
}
