// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// The per-project scope's family handle and cache eviction.
///
/// The API this replaces (`perProjectScopeFamily`) built a *brand-new*
/// `Provider.family` from the same name and returned it. Riverpod identifies
/// providers by object identity, not by name, so the returned family was a
/// different slot from the one `perProjectScope` reads: the documented use —
/// "seed initial state for a specific project id" — wrote somewhere nothing
/// ever read. It was publicly exported with zero real call sites, so a Pro
/// overlay following the doc would have got a silent no-op.

// The family's inferred type is long and adds nothing here.
// ignore: specify_nonobvious_property_types
final _counterFamily = StateProvider.family<int, String>((_, _) => 0);

final PerProjectScope<int> _scope = perProjectScopeWithFamily<int>(
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

ProviderContainer _boot(_FakeRegistry registry) {
  final container = ProviderContainer(
    overrides: <Override>[projectRegistryProvider.overrideWithValue(registry)],
  );
  addTearDown(container.dispose);
  container.listen<AsyncValue<ProjectWorkspace>>(
    projectWorkspaceProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

void main() {
  group('the exposed family is the SLOT THE PROVIDER READS', () {
    test('overriding the exposed family changes what the provider reads', () {
      // THE test the old API could not pass. Seeding a per-project slot means
      // overriding the family the provider actually watches; with the old
      // standalone helper this override targeted an unrelated provider object
      // and the assertion below would read the un-overridden 0.
      final registry = _FakeRegistry();
      final container = ProviderContainer(
        overrides: <Override>[
          projectRegistryProvider.overrideWithValue(registry),
          _scope.family.overrideWith((ref, projectId) => 55),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(_scope.provider),
        55,
        reason: 'the family handed back must be the provider’s own slot',
      );
    });

    test('reading the family directly agrees with the provider', () async {
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..setActiveProjectSync('a');
      await _pump();
      container.read(_counterFamily('a').notifier).state = 55;

      expect(container.read(_scope.family('a')), 55);
      expect(container.read(_scope.provider), 55);
    });

    test('a separately-constructed same-named family is a DIFFERENT slot', () {
      // Pins the reason the old helper was broken, so nobody reintroduces it.
      final a = perProjectScopeWithFamily<int>('dup', (ref, id) => 1);
      final b = perProjectScopeWithFamily<int>('dup', (ref, id) => 1);

      expect(
        identical(a.family, b.family),
        isFalse,
        reason: 'identical names do NOT make identical providers in Riverpod',
      );
    });

    test('the sentinel id is addressable for the no-project case', () async {
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      container.read(_counterFamily(emptyWorkspaceProjectId).notifier).state =
          3;

      expect(container.read(_scope.provider), 3);
    });

    test('perProjectScope still returns a bare Provider', () async {
      final plain = perProjectScope<int>('plain', (ref, id) => 7);
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      expect(container.read(plain), 7);
    });

    test('state is still retained across a -> b -> a switches', () async {
      // The eviction work must not regress the retention guarantee.
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..setActiveProjectSync('a');
      await _pump();
      container.read(_counterFamily('a').notifier).state = 11;

      registry
        ..openSync(_desc('b'))
        ..setActiveProjectSync('b');
      await _pump();
      container.read(_counterFamily('b').notifier).state = 22;
      expect(container.read(_scope.provider), 22);

      registry.setActiveProjectSync('a');
      await _pump();
      expect(container.read(_scope.provider), 11);

      registry.setActiveProjectSync('b');
      await _pump();
      expect(container.read(_scope.provider), 22);
    });
  });

  group('cache retention is explicit, not magical', () {
    test(
      'state is retained until the host evicts — no automatic drop',
      () async {
        // Automatic eviction driven off the workspace's known-project set was
        // evaluated and rejected: it fires on transient unresolved
        // snapshots and drops state at a moment the product did not
        // choose. Retention is the documented behaviour, so pin it.
        final registry = _FakeRegistry();
        final container = _boot(registry);
        await _pump();

        registry
          ..openSync(_desc('a'))
          ..openSync(_desc('b'))
          ..setActiveProjectSync('a');
        await _pump();
        container.read(_counterFamily('a').notifier).state = 11;

        // Hard-remove 'a' entirely: gone from open AND from recents.
        registry
          ..setActiveProjectSync('b')
          ..hardRemove('a');
        await _pump();
        container.read(_scope.provider);

        registry
          ..openSync(_desc('a'))
          ..setActiveProjectSync('a');
        await _pump();
        expect(
          container.read(_scope.provider),
          11,
          reason: "nothing evicts behind the host's back",
        );
      },
    );

    test("evictProject drops the scope's cached wrapper", () async {
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..setActiveProjectSync('a');
      await _pump();
      expect(container.read(_scope.family('a')), 0);

      // Seed, then evict: the wrapper is rebuilt from the underlying family
      // on the next read, so a host that also resets its own family gets a
      // genuinely clean project.
      container.read(_counterFamily('a').notifier).state = 4;
      expect(container.read(_scope.family('a')), 4);

      _scope.evictProject(container, 'a');
      container.read(_counterFamily('a').notifier).state = 0;

      expect(
        container.read(_scope.family('a')),
        0,
        reason: 'the wrapper re-derives after eviction',
      );
    });

    test('evicting an inactive project leaves the active one alone', () async {
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..openSync(_desc('b'))
        ..setActiveProjectSync('a');
      await _pump();
      container.read(_counterFamily('a').notifier).state = 11;
      container.read(_counterFamily('b').notifier).state = 22;
      expect(container.read(_scope.provider), 11);

      _scope.evictProject(container, 'b');

      expect(
        container.read(_scope.provider),
        11,
        reason: 'evicting another project must not disturb the active one',
      );
    });

    test('a hard-removed active project falls back to the sentinel', () async {
      final registry = _FakeRegistry();
      final container = _boot(registry);
      await _pump();

      registry
        ..openSync(_desc('a'))
        ..setActiveProjectSync('a');
      await _pump();
      container.read(_counterFamily('a').notifier).state = 9;
      expect(container.read(_scope.provider), 9);

      // With no project open the scope resolves the empty-workspace sentinel
      // rather than throwing or serving a stale project's state.
      registry.hardRemove('a');
      await _pump();

      expect(container.read(_scope.provider), 0);
    });
  });
}

/// Synchronous registry double with explicit soft-close (moves to recents)
/// and hard-remove (drops entirely) so the eviction boundary is testable.
class _FakeRegistry implements ProjectRegistry {
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
      openProjects: <ProjectDescriptor>[
        ..._ws.openProjects.where((p) => p.id != d.id),
        d,
      ],
      activeProjectId: d.id,
      recentProjects: _ws.recentProjects
          .where((p) => p.id != d.id)
          .toList(growable: false),
    );
    _publish();
  }

  void setActiveProjectSync(String id) {
    if (!_ws.openProjects.any((p) => p.id == id)) return;
    _ws = _ws.copyWith(activeProjectId: id);
    _publish();
  }

  /// Close to recents — the retention window.
  void softClose(String id) {
    final closing = _ws.openProjects.where((p) => p.id == id).toList();
    _ws = ProjectWorkspace(
      openProjects: _ws.openProjects
          .where((p) => p.id != id)
          .toList(growable: false),
      activeProjectId: _ws.activeProjectId == id ? null : _ws.activeProjectId,
      recentProjects: <ProjectDescriptor>[...closing, ..._ws.recentProjects],
    );
    _publish();
  }

  /// Drop from open AND recents — past the retention window.
  void hardRemove(String id) {
    _ws = ProjectWorkspace(
      openProjects: _ws.openProjects
          .where((p) => p.id != id)
          .toList(growable: false),
      activeProjectId: _ws.activeProjectId,
      recentProjects: _ws.recentProjects
          .where((p) => p.id != id)
          .toList(growable: false),
    );
    _publish();
  }

  @override
  ProjectWorkspace get current => _ws;

  @override
  Stream<ProjectWorkspace> watch() {
    late StreamController<ProjectWorkspace> c;
    c = StreamController<ProjectWorkspace>(
      onListen: () => c.add(_ws),
      onCancel: () => _subs.remove(c),
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
  Future<void> closeProject(String projectId, {bool hardClose = false}) async {
    hardClose ? hardRemove(projectId) : softClose(projectId);
  }

  @override
  Future<void> closeAllProjects() async {}

  @override
  Future<void> setActiveProject(String projectId) async =>
      setActiveProjectSync(projectId);

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) async {}

  @override
  Future<void> reorderProjects(List<String> newOrderIds) async {}

  @override
  Future<void> clearRecentProject(String projectId) async =>
      hardRemove(projectId);

  @override
  Future<void> shutdownAll() async {}
}
