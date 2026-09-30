// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:crux_projects_ui/crux_projects_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestStrings implements CruxProjectsUiStrings {
  @override
  String get switcherTitle => 'Switch Project';
  @override
  String get switcherDismissTooltip => 'Dismiss';
  @override
  String get switcherSearchHint => 'Filter projects';
  @override
  String get switcherSectionOpen => 'Open';
  @override
  String get switcherSectionRecent => 'Recent';
  @override
  String get switcherEmptyOpen => 'No open projects';
  @override
  String get switcherEmptyRecent => 'No recent projects';
  @override
  String get switcherEmptySearch => 'Nothing matches';
  @override
  String get switcherActionClose => 'Close';
  @override
  String get switcherActionForget => 'Forget';
  @override
  String get switcherActiveIndicator => 'ACTIVE';
  @override
  String get switcherFooterSearchAcrossProjects => 'Search across projects';
  @override
  String get recentsPanelTitle => 'Recent Projects';
  @override
  String get recentsPanelEmpty => 'Nothing here yet';
  @override
  String get recentsPanelReopen => 'Reopen';
  @override
  String get recentsPanelForget => 'Forget';
}

/// Records what the dialog asks the registry to do.
class _FakeRegistry implements ProjectRegistry {
  _FakeRegistry(this._workspace, {this.missing = const <String>{}});

  final ProjectWorkspace _workspace;

  /// Paths [openProject] refuses, as a persistent registry refuses a path
  /// that is no longer on disk.
  final Set<String> missing;
  final _controller = StreamController<ProjectWorkspace>.broadcast();

  String? activatedId;
  String? openedPath;
  String? closedId;
  String? clearedRecentId;

  @override
  ProjectWorkspace get current => _workspace;

  @override
  Stream<ProjectWorkspace> watch() async* {
    yield _workspace;
    yield* _controller.stream;
  }

  @override
  Future<void> setActiveProject(String projectId) async {
    activatedId = projectId;
  }

  @override
  Future<ProjectDescriptor> openProject(String projectPath) async {
    if (missing.contains(projectPath)) {
      throw ProjectLoadException(projectPath, 'path does not exist');
    }
    openedPath = projectPath;
    return _d(projectPath);
  }

  @override
  Future<void> closeProject(String projectId, {bool hardClose = false}) async {
    closedId = projectId;
  }

  @override
  Future<void> clearRecentProject(String projectId) async {
    clearedRecentId = projectId;
  }

  @override
  Future<void> closeAllProjects() async {}

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) async {}

  @override
  Future<void> reorderProjects(List<String> newOrderIds) async {}

  @override
  Future<void> shutdownAll() async {}

  void dispose() => _controller.close();
}

final _t = DateTime.utc(2026, 7, 30);

ProjectDescriptor _d(String name, {bool pinned = false}) => ProjectDescriptor(
  id: 'id-$name',
  displayName: name,
  projectPath: '/p/$name',
  loadedAt: _t,
  lastAccessedAt: _t,
  isPinned: pinned,
);

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: Scaffold(body: Dialog(child: CruxProjectSwitcherDialog())),
  ),
);

ProviderContainer _container(
  _FakeRegistry registry, {
  CruxCrossProjectSearchOpener? searchOpener,
  CruxProjectsUiBadgeBuilder? badge,
  CruxRecentProjectUnavailableReporter? unavailableReporter,
  ProjectActivationObserver? activationObserver,
}) {
  return ProviderContainer(
    overrides: [
      projectRegistryProvider.overrideWithValue(registry),
      cruxProjectsUiStringsProvider.overrideWithValue(_TestStrings()),
      if (searchOpener != null)
        crossProjectSearchOpenerProvider.overrideWithValue(searchOpener),
      if (badge != null)
        cruxProjectsUiBadgeBuilderProvider.overrideWithValue(badge),
      if (unavailableReporter != null)
        recentProjectUnavailableReporterProvider.overrideWithValue(
          unavailableReporter,
        ),
      if (activationObserver != null)
        projectActivationObserverProvider.overrideWithValue(activationObserver),
    ],
  );
}

void main() {
  late _FakeRegistry registry;

  tearDown(() => registry.dispose());

  testWidgets('lists open and recent projects in their sections', (
    tester,
  ) async {
    registry = _FakeRegistry(
      ProjectWorkspace(
        openProjects: [_d('alpha')],
        recentProjects: [_d('bravo')],
        activeProjectId: 'id-alpha',
      ),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('bravo'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('selecting an open project activates it', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha')]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    expect(registry.activatedId, 'id-alpha');
    expect(registry.openedPath, isNull);
  });

  testWidgets('selecting a recent project opens it by path', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(recentProjects: [_d('bravo')]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bravo'));
    await tester.pumpAndSettle();

    expect(registry.openedPath, '/p/bravo');
    expect(registry.activatedId, isNull);
  });

  testWidgets('a recent project that can no longer be opened is reported and '
      'forgotten, and is not an activation', (tester) async {
    // A persistent registry refuses a path that has gone from disk and keeps
    // the entry. Unhandled, the selection failed with nothing shown, and the
    // entry stayed to fail the same way next time.
    registry = _FakeRegistry(
      ProjectWorkspace(recentProjects: [_d('bravo')]),
      missing: {'/p/bravo'},
    );
    final reported = <ProjectDescriptor>[];
    final activations = <ProjectActivation>[];
    final container = _container(
      registry,
      unavailableReporter: (context, recent, error) => reported.add(recent),
      activationObserver: activations.add,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bravo'));
    await tester.pumpAndSettle();

    expect(reported.map((d) => d.id), ['id-bravo']);
    expect(registry.clearedRecentId, 'id-bravo');
    expect(registry.openedPath, isNull);
    expect(activations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('per-row Close and Forget route to the registry', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(
        openProjects: [_d('alpha')],
        recentProjects: [_d('bravo')],
      ),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(registry.closedId, 'id-alpha');

    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(registry.clearedRecentId, 'id-bravo');
  });

  testWidgets('the filter matches display name and path', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha'), _d('bravo')]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'alph');
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('bravo'), findsNothing);
  });

  testWidgets('an unmatched filter says so rather than showing an empty '
      'open-projects message', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha')]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches'), findsOneWidget);
  });

  testWidgets('the cross-project-search footer is hidden when no opener is '
      'installed — a product without the feature must not advertise it', (
    tester,
  ) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha')]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Search across projects'), findsNothing);
  });

  testWidgets('the footer appears and fires when an opener is installed', (
    tester,
  ) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha')]),
    );
    var opened = 0;
    final container = _container(
      registry,
      searchOpener: (_) => opened++,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Search across projects'), findsOneWidget);
    await tester.tap(find.text('Search across projects'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('renders the host badge when one is supplied', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha')]),
    );
    final container = _container(
      registry,
      badge: (_) => const Text('PRO'),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('PRO'), findsOneWidget);
  });

  testWidgets('renders no badge by default', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha')]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('PRO'), findsNothing);
  });

  testWidgets('a pinned project renders the pin icon', (tester) async {
    registry = _FakeRegistry(
      ProjectWorkspace(openProjects: [_d('alpha', pinned: true)]),
    );
    final container = _container(registry);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('unbound strings throw with an actionable message', (
    tester,
  ) async {
    registry = _FakeRegistry(ProjectWorkspace.empty());
    final container = ProviderContainer(
      overrides: [projectRegistryProvider.overrideWithValue(registry)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pump();

    // Riverpod 3 wraps a provider-body throw in ProviderException, so
    // assert on the message rather than the type — the message is the
    // part that has to tell a host developer what to do.
    final error = tester.takeException();
    expect(
      error.toString(),
      allOf(
        contains('cruxProjectsUiStringsProvider'),
        contains('override'),
      ),
    );
  });
}
