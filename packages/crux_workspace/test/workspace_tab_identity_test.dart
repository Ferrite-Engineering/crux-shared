// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Payload shaped like every product's: a file path plus a display concern.
/// The empty path stands for a blank scratch tab, which must stay openable
/// more than once.
@immutable
class _ProjectPayload {
  const _ProjectPayload(this.projectPath);

  final String projectPath;

  @override
  bool operator ==(Object other) =>
      other is _ProjectPayload && other.projectPath == projectPath;

  @override
  int get hashCode => projectPath.hashCode;
}

/// Codec that opts in to identity the way products are expected to — through
/// `canonicalPathKey`, not the raw string.
class _PathIdentityCodec extends WorkspaceCodec<_ProjectPayload> {
  const _PathIdentityCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(_ProjectPayload payload) => {
    'projectPath': payload.projectPath,
  };

  @override
  _ProjectPayload payloadFromJson(Map<String, Object?> json) =>
      _ProjectPayload(json['projectPath'] as String? ?? '');

  @override
  String displayNameFor(_ProjectPayload payload) => payload.projectPath.isEmpty
      ? 'Untitled'
      : p.basename(payload.projectPath);

  @override
  String? identityOf(_ProjectPayload payload) {
    if (payload.projectPath.trim().isEmpty) return null;
    return canonicalPathKey(payload.projectPath);
  }
}

/// The pre-fix codec: no identity at all. Pins that products which have not
/// opted in keep their old behaviour exactly.
class _NoIdentityCodec extends _PathIdentityCodec {
  const _NoIdentityCodec();

  @override
  String? identityOf(_ProjectPayload payload) => null;
}

class _Harness {
  _Harness({
    required this.tempDir,
    WorkspaceCodec<_ProjectPayload> codec = const _PathIdentityCodec(),
    Future<bool> Function()? shouldRestore,
  }) : service = WorkspaceService<_ProjectPayload>(
         codec: codec,
         directoryFactory: () async => tempDir,
         logger: (_) {},
       ) {
    provider =
        AsyncNotifierProvider<
          WorkspaceNotifier<_ProjectPayload>,
          Workspace<_ProjectPayload>
        >(
          () => shouldRestore == null
              ? WorkspaceNotifier<_ProjectPayload>(
                  service: service,
                  autoSaveDebounce: Duration.zero,
                )
              : _GatedNotifier(
                  service: service,
                  shouldRestore: shouldRestore,
                ),
        );
    container = ProviderContainer();
  }

  final Directory tempDir;
  final WorkspaceService<_ProjectPayload> service;
  late final AsyncNotifierProvider<
    WorkspaceNotifier<_ProjectPayload>,
    Workspace<_ProjectPayload>
  >
  provider;
  late final ProviderContainer container;

  Future<void> hydrate() => container.read(provider.future);
  WorkspaceNotifier<_ProjectPayload> get notifier =>
      container.read(provider.notifier);
  Workspace<_ProjectPayload> get state => container.read(provider).requireValue;

  /// Opens [path] the way a CLI launch does.
  Future<TabId> cliOpen(String path) => notifier.openTab(
    displayName: p.basename(path),
    payload: _ProjectPayload(path),
  );

  Future<void> dispose() async {
    await notifier.flushPendingSave();
    container.dispose();
  }
}

/// A product-style subclass that gates restore on a preference.
class _GatedNotifier extends WorkspaceNotifier<_ProjectPayload> {
  _GatedNotifier({
    required super.service,
    required this.shouldRestore,
  }) : super(autoSaveDebounce: Duration.zero);

  final Future<bool> Function() shouldRestore;

  @override
  Future<bool> shouldRestoreOnLaunch() => shouldRestore();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String projectPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_ws_identity_');
    final file = File(p.join(tempDir.path, 'sub', 'riscv-soc.project'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{}');
    projectPath = file.path;
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('tab identity dedupe', () {
    test('a second open of the same path focuses the first tab', () async {
      final h = _Harness(tempDir: tempDir);
      addTearDown(h.dispose);
      await h.hydrate();

      final first = await h.cliOpen(projectPath);
      await h.notifier.openTab(
        displayName: 'other',
        payload: const _ProjectPayload('/elsewhere/other.project'),
      );
      expect(h.state.tabs, hasLength(2));
      expect(h.state.activeTabId, isNot(first));

      final second = await h.cliOpen(projectPath);

      expect(second, first, reason: 'The existing tab must be reused.');
      expect(h.state.tabs, hasLength(2));
      expect(
        h.state.activeTabId,
        first,
        reason: 'A CLI open of an already-open project focuses it.',
      );
    });

    test('repeated relaunches do not accumulate tabs without bound', () async {
      // The shipped symptom: one project reached seven tabs, one per launch.
      final h = _Harness(tempDir: tempDir);
      addTearDown(h.dispose);
      await h.hydrate();

      for (var i = 0; i < 7; i++) {
        await h.cliOpen(projectPath);
      }

      expect(h.state.tabs, hasLength(1));
    });

    group('identity survives path spellings that a raw string does not', () {
      test('relative vs absolute', () async {
        final h = _Harness(tempDir: tempDir);
        addTearDown(h.dispose);
        await h.hydrate();

        final previous = Directory.current;
        Directory.current = tempDir;
        addTearDown(() => Directory.current = previous);

        final first = await h.cliOpen(projectPath);
        final second = await h.cliOpen(p.join('sub', 'riscv-soc.project'));

        expect(second, first);
        expect(h.state.tabs, hasLength(1));
      });

      test('dot and dot-dot segments', () async {
        final h = _Harness(tempDir: tempDir);
        addTearDown(h.dispose);
        await h.hydrate();

        final first = await h.cliOpen(projectPath);
        final second = await h.cliOpen(
          p.join(tempDir.path, 'sub', '..', 'sub', '.', 'riscv-soc.project'),
        );

        expect(second, first);
        expect(h.state.tabs, hasLength(1));
      });

      test('trailing separator on a directory-shaped project path', () async {
        final dir = Directory(p.join(tempDir.path, 'bundle.project'))
          ..createSync();
        final h = _Harness(tempDir: tempDir);
        addTearDown(h.dispose);
        await h.hydrate();

        final first = await h.cliOpen(dir.path);
        final second = await h.cliOpen('${dir.path}${p.separator}');

        expect(second, first);
        expect(h.state.tabs, hasLength(1));
      });

      test('symlinked path', () async {
        final link = Link(p.join(tempDir.path, 'alias.project'))
          ..createSync(projectPath);
        final h = _Harness(tempDir: tempDir);
        addTearDown(h.dispose);
        await h.hydrate();

        final first = await h.cliOpen(projectPath);
        final second = await h.cliOpen(link.path);

        expect(second, first);
        expect(h.state.tabs, hasLength(1));
      });

      test('case difference on a case-insensitive filesystem', () async {
        final h = _Harness(tempDir: tempDir);
        addTearDown(h.dispose);
        await h.hydrate();

        final first = await h.cliOpen(projectPath);
        final second = await h.cliOpen(projectPath.toUpperCase());

        if (filesystemIsCaseInsensitive) {
          expect(second, first);
          expect(h.state.tabs, hasLength(1));
        } else {
          expect(second, isNot(first));
          expect(h.state.tabs, hasLength(2));
        }
      });
    });

    test('identity-less payloads still open a tab each', () async {
      // Two blank scratch tabs are two tabs. Folding every null identity
      // together would make the second one impossible to create.
      final h = _Harness(tempDir: tempDir);
      addTearDown(h.dispose);
      await h.hydrate();

      await h.notifier.openTab(
        displayName: 'Untitled',
        payload: const _ProjectPayload(''),
      );
      await h.notifier.openTab(
        displayName: 'Untitled',
        payload: const _ProjectPayload(''),
      );

      expect(h.state.tabs, hasLength(2));
    });

    test('a codec that has not opted in keeps the old behaviour', () async {
      final h = _Harness(tempDir: tempDir, codec: const _NoIdentityCodec());
      addTearDown(h.dispose);
      await h.hydrate();

      await h.cliOpen(projectPath);
      await h.cliOpen(projectPath);

      expect(
        h.state.tabs,
        hasLength(2),
        reason:
            'identityOf defaults to null, so dedupe cannot change behaviour '
            'behind a product that has not opted in.',
      );
    });

    test('dedupe: false opens a deliberate second view', () async {
      final h = _Harness(tempDir: tempDir);
      addTearDown(h.dispose);
      await h.hydrate();

      final first = await h.cliOpen(projectPath);
      final second = await h.notifier.openTab(
        displayName: 'riscv-soc',
        payload: _ProjectPayload(projectPath),
        dedupe: false,
      );

      expect(second, isNot(first));
      expect(h.state.tabs, hasLength(2));
    });

    test('dedupe matches a tab rehydrated from disk, not just one opened '
        'this session', () async {
      // This is the actual bug: the duplicate is the *restored* tab plus the
      // fresh CLI one, so the match has to survive a serialize/deserialize
      // round trip.
      final first = _Harness(tempDir: tempDir);
      await first.hydrate();
      final restoredId = await first.cliOpen(projectPath);
      await first.notifier.flushPendingSave();
      first.container.dispose();

      final relaunch = _Harness(tempDir: tempDir);
      addTearDown(relaunch.dispose);
      await relaunch.hydrate();
      expect(relaunch.state.tabs, hasLength(1));

      final cliId = await relaunch.cliOpen(projectPath);

      expect(cliId, restoredId);
      expect(relaunch.state.tabs, hasLength(1));
      expect(relaunch.state.activeTabId, restoredId);
    });

    test('tabWithSameIdentityAs reports the match without mutating', () async {
      final h = _Harness(tempDir: tempDir);
      addTearDown(h.dispose);
      await h.hydrate();

      expect(
        h.notifier.tabWithSameIdentityAs(_ProjectPayload(projectPath)),
        isNull,
      );

      final id = await h.cliOpen(projectPath);

      expect(
        h.notifier.tabWithSameIdentityAs(_ProjectPayload(projectPath)),
        id,
      );
      expect(
        h.notifier.tabWithSameIdentityAs(const _ProjectPayload('')),
        isNull,
      );
      expect(h.state.tabs, hasLength(1));
    });

    test('focusing a deduped tab also focuses its pane', () async {
      final h = _Harness(tempDir: tempDir);
      addTearDown(h.dispose);
      await h.hydrate();

      final restored = await h.cliOpen(projectPath);
      await h.notifier.splitPaneRight();
      await h.notifier.openTab(
        displayName: 'other',
        payload: const _ProjectPayload('/elsewhere/other.project'),
      );
      final otherPane = h.state.activePaneId;
      final restoredPane = h.state.tabs
          .firstWhere((t) => t.id == restored)
          .paneId;
      expect(otherPane, isNot(restoredPane));

      await h.cliOpen(projectPath);

      expect(h.state.activePaneId, restoredPane);
      expect(h.state.activeTabId, restored);
    });
  });

  group('restore-on-launch gate', () {
    test('restore enabled rehydrates the persisted document', () async {
      final first = _Harness(tempDir: tempDir);
      await first.hydrate();
      await first.cliOpen(projectPath);
      await first.notifier.flushPendingSave();
      first.container.dispose();

      final relaunch = _Harness(
        tempDir: tempDir,
        shouldRestore: () async => true,
      );
      addTearDown(relaunch.dispose);
      await relaunch.hydrate();

      expect(relaunch.state.tabs, hasLength(1));
    });

    test('restore disabled starts clean', () async {
      final first = _Harness(tempDir: tempDir);
      await first.hydrate();
      await first.cliOpen(projectPath);
      await first.notifier.flushPendingSave();
      first.container.dispose();

      final relaunch = _Harness(
        tempDir: tempDir,
        shouldRestore: () async => false,
      );
      addTearDown(relaunch.dispose);
      await relaunch.hydrate();

      expect(relaunch.state.tabs, isEmpty);
    });

    test('restore disabled leaves the document on disk', () async {
      final first = _Harness(tempDir: tempDir);
      await first.hydrate();
      await first.cliOpen(projectPath);
      await first.notifier.flushPendingSave();
      first.container.dispose();

      final documentBefore = File(
        p.join(tempDir.path, 'workspace.json'),
      ).readAsStringSync();

      final relaunch = _Harness(
        tempDir: tempDir,
        shouldRestore: () async => false,
      );
      await relaunch.hydrate();
      relaunch.container.dispose();

      expect(
        File(p.join(tempDir.path, 'workspace.json')).readAsStringSync(),
        documentBefore,
        reason:
            'Declining to restore must not destroy the session — flipping '
            'the preference back on has to bring the tabs back.',
      );
    });

    test(
      'restore disabled + a CLI argument yields exactly the CLI tab',
      () async {
        final first = _Harness(tempDir: tempDir);
        await first.hydrate();
        await first.cliOpen(projectPath);
        await first.notifier.openTab(
          displayName: 'stale',
          payload: const _ProjectPayload('/gone/stale.project'),
        );
        await first.notifier.flushPendingSave();
        first.container.dispose();

        final relaunch = _Harness(
          tempDir: tempDir,
          shouldRestore: () async => false,
        );
        addTearDown(relaunch.dispose);
        await relaunch.hydrate();
        await relaunch.cliOpen(projectPath);

        expect(relaunch.state.tabs, hasLength(1));
        expect(
          relaunch.state.tabs.single.payload.projectPath,
          projectPath,
        );
      },
    );

    test('restore enabled + a CLI argument yields the restored tabs plus '
        'exactly one deduped CLI tab', () async {
      final first = _Harness(tempDir: tempDir);
      await first.hydrate();
      await first.cliOpen(projectPath);
      await first.notifier.openTab(
        displayName: 'other',
        payload: const _ProjectPayload('/elsewhere/other.project'),
      );
      await first.notifier.flushPendingSave();
      first.container.dispose();

      final relaunch = _Harness(
        tempDir: tempDir,
        shouldRestore: () async => true,
      );
      addTearDown(relaunch.dispose);
      await relaunch.hydrate();
      expect(relaunch.state.tabs, hasLength(2));

      await relaunch.cliOpen(projectPath);
      await relaunch.cliOpen(p.join(tempDir.path, 'sub', 'fresh.project'));

      expect(relaunch.state.tabs, hasLength(3));
      expect(
        relaunch.state.tabs
            .where((t) => t.payload.projectPath == projectPath)
            .length,
        1,
      );
    });

    test('the gate is consulted before the document is read', () async {
      var loadCalled = false;
      final probe = _RecordingService(
        tempDir: tempDir,
        onLoad: () => loadCalled = true,
      );
      final provider =
          AsyncNotifierProvider<
            WorkspaceNotifier<_ProjectPayload>,
            Workspace<_ProjectPayload>
          >(
            () => _GatedNotifier(
              service: probe,
              shouldRestore: () async => false,
            ),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(provider.future);

      expect(
        loadCalled,
        isFalse,
        reason:
            'Closing restored tabs after the fact still pays for the load '
            'and still emits a scope reconcile for tabs it discards.',
      );
    });
  });
}

/// Service that records whether [load] was reached.
class _RecordingService extends WorkspaceService<_ProjectPayload> {
  _RecordingService({required Directory tempDir, required this.onLoad})
    : super(
        codec: const _PathIdentityCodec(),
        directoryFactory: () async => tempDir,
        logger: (_) {},
      );

  final void Function() onLoad;

  @override
  Future<Workspace<_ProjectPayload>> load() {
    onLoad();
    return super.load();
  }
}
