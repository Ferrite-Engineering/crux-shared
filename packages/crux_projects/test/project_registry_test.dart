// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopProjectRegistry', () {
    test(
      'openProject sets the project active and replaces any prior',
      () async {
        final registry = NoopProjectRegistry();
        final a = await registry.openProject('/projects/a.proj');
        expect(registry.current.openProjects, hasLength(1));
        expect(registry.current.activeProjectId, a.id);

        final b = await registry.openProject('/projects/b.proj');
        expect(registry.current.openProjects, hasLength(1));
        expect(registry.current.activeProjectId, b.id);
        expect(registry.current.openProjects.single.id, b.id);
      },
    );

    test('closeProject hard-clears: recentProjects always empty', () async {
      final registry = NoopProjectRegistry();
      final a = await registry.openProject('/projects/a.proj');
      await registry.closeProject(a.id);
      expect(registry.current.openProjects, isEmpty);
      expect(registry.current.recentProjects, isEmpty);
      expect(registry.current.activeProjectId, isNull);
    });

    test(
      'pinProject / reorderProjects / clearRecentProject are no-ops',
      () async {
        final registry = NoopProjectRegistry();
        final a = await registry.openProject('/projects/a.proj');
        await registry.pinProject(a.id, pinned: true);
        // Pinning in single-project mode is a no-op — project stays unpinned.
        expect(registry.current.openProjects.single.isPinned, isFalse);

        await registry.reorderProjects(<String>[a.id]);
        await registry.clearRecentProject(a.id);
        expect(registry.current.openProjects.single.id, a.id);
      },
    );

    test(
      'watch() emits the current snapshot on subscribe and on mutation',
      () async {
        final registry = NoopProjectRegistry();
        final events = <int>[];
        final sub = registry.watch().listen((ws) => events.add(ws.openCount));

        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(events.last, 0);

        await registry.openProject('/projects/a.proj');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(events.last, 1);

        await sub.cancel();
      },
    );

    test('setActiveProject no-ops when id is not currently open', () async {
      final registry = NoopProjectRegistry();
      await registry.setActiveProject('bogus');
      expect(registry.current.activeProjectId, isNull);
    });

    test('shutdownAll empties the workspace', () async {
      final registry = NoopProjectRegistry();
      await registry.openProject('/projects/a.proj');
      await registry.shutdownAll();
      expect(registry.current.openProjects, isEmpty);
      expect(registry.current.recentProjects, isEmpty);
      expect(registry.current.activeProjectId, isNull);
    });

    test('closeAllProjects empties the workspace', () async {
      final registry = NoopProjectRegistry();
      await registry.openProject('/projects/a.proj');
      await registry.closeAllProjects();
      expect(registry.current.openProjects, isEmpty);
    });
  });
}
