// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Demonstrative per-project state — a simple counter keyed per project. Real
/// features replace this with their own NotifierProvider.family. The shape
/// under `perProjectScope` is identical regardless of the underlying family
/// provider type.
// ignore: specify_nonobvious_property_types
final _counterFamily = StateProvider.family<int, String>((_, _) => 0);

final Provider<int> _counterProvider = perProjectScope<int>(
  'test_counter',
  (ref, projectId) => ref.watch(_counterFamily(projectId)),
);

ProjectDescriptor _desc(String id) {
  final t = DateTime.utc(2026, 3);
  return ProjectDescriptor(
    id: id,
    displayName: '$id.proj',
    projectPath: '/projects/$id.proj',
    loadedAt: t,
    lastAccessedAt: t,
  );
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('per-project scope: returns family state for active project', () async {
    final registry = _FakeMultiProjectRegistry();
    final container = ProviderContainer(
      overrides: <Override>[
        projectRegistryProvider.overrideWithValue(registry),
      ],
    );
    addTearDown(container.dispose);
    container.listen<AsyncValue<ProjectWorkspace>>(
      projectWorkspaceProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await _pump();

    // No project open → empty-workspace sentinel id used.
    expect(container.read(_counterProvider), 0);
    container.read(_counterFamily(emptyWorkspaceProjectId).notifier).state = 7;
    expect(container.read(_counterProvider), 7);
  });

  test(
    'per-project scope: state is retained across active-project switches',
    () async {
      final registry = _FakeMultiProjectRegistry();
      final container = ProviderContainer(
        overrides: <Override>[
          projectRegistryProvider.overrideWithValue(registry),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<ProjectWorkspace>>(
        projectWorkspaceProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..setActiveProjectSync('a');
      await _pump();

      // Project a active; seed its counter.
      container.read(_counterFamily('a').notifier).state = 11;
      expect(container.read(_counterProvider), 11);

      // Open b, switch active. Project b starts fresh.
      registry
        ..openSync(_desc('b'))
        ..setActiveProjectSync('b');
      await _pump();
      expect(container.read(_counterProvider), 0);

      // Seed b's counter, switch back to a, verify a's state retained.
      container.read(_counterFamily('b').notifier).state = 22;
      expect(container.read(_counterProvider), 22);
      registry.setActiveProjectSync('a');
      await _pump();
      expect(container.read(_counterProvider), 11);

      // Project b's state survives a → b switch back too.
      registry.setActiveProjectSync('b');
      await _pump();
      expect(container.read(_counterProvider), 22);
    },
  );
}

/// Synchronous test-double registry that appends rather than replacing. The
/// open-core [NoopProjectRegistry] replaces; the Pro overlays' persistent
/// registry appends. This double lets the scope-isolation tests exercise the
/// multi-project flow without a real filesystem or the Pro implementation.
class _FakeMultiProjectRegistry implements ProjectRegistry {
  ProjectWorkspace _ws = ProjectWorkspace.empty();
  final List<StreamController<ProjectWorkspace>> _subs =
      <StreamController<ProjectWorkspace>>[];

  void _publish() {
    for (final s in _subs) {
      if (!s.isClosed) s.add(_ws);
    }
  }

  void openSync(ProjectDescriptor d) {
    _ws = ProjectWorkspace(
      openProjects: <ProjectDescriptor>[..._ws.openProjects, d],
      activeProjectId: d.id,
      recentProjects: _ws.recentProjects,
    );
    _publish();
  }

  void setActiveProjectSync(String id) {
    if (!_ws.openProjects.any((p) => p.id == id)) return;
    _ws = _ws.copyWith(activeProjectId: id);
    _publish();
  }

  @override
  ProjectWorkspace get current => _ws;

  @override
  Stream<ProjectWorkspace> watch() {
    late StreamController<ProjectWorkspace> c;
    c = StreamController<ProjectWorkspace>(
      onListen: () {
        c.add(_ws);
      },
      onCancel: () {
        _subs.remove(c);
      },
    );
    _subs.add(c);
    return c.stream;
  }

  @override
  Future<ProjectDescriptor> openProject(String projectPath) async {
    final d = _desc(ProjectDescriptor.idForPath(projectPath));
    openSync(d);
    return d;
  }

  @override
  Future<void> closeProject(String projectId, {bool hardClose = false}) async {}

  @override
  Future<void> closeAllProjects() async {}

  @override
  Future<void> setActiveProject(String projectId) async {
    setActiveProjectSync(projectId);
  }

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) async {}

  @override
  Future<void> reorderProjects(List<String> newOrderIds) async {}

  @override
  Future<void> clearRecentProject(String projectId) async {}

  @override
  Future<void> shutdownAll() async {}
}
