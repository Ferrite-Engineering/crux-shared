// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:crux_projects_ui/crux_projects_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Reopen on a recent project whose folder has gone since it was closed.
///
/// A persistent registry refuses that path with a [ProjectLoadException] and
/// keeps the entry. The panel fired the open and forgot it, so the press did
/// nothing anyone could see, the error went uncaught, and the row stayed to
/// fail the same way on the next press.
void main() {
  late _ReactiveRegistry registry;
  late List<(ProjectDescriptor, ProjectLoadException)> reported;
  late List<ProjectActivation> activations;

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<ProjectDescriptor> recents,
    Set<String> missing = const <String>{},
    bool bindReporter = true,
  }) async {
    registry = _ReactiveRegistry(recents, missing: missing);
    addTearDown(registry.dispose);
    reported = <(ProjectDescriptor, ProjectLoadException)>[];
    activations = <ProjectActivation>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          projectRegistryProvider.overrideWithValue(registry),
          cruxProjectsUiStringsProvider.overrideWithValue(_TestStrings()),
          projectActivationObserverProvider.overrideWithValue(activations.add),
          if (bindReporter)
            recentProjectUnavailableReporterProvider.overrideWithValue(
              (context, recent, error) => reported.add((recent, error)),
            ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CruxRecentProjectsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressReopen(WidgetTester tester, String name) async {
    final row = find.ancestor(of: find.text(name), matching: find.byType(Row));
    await tester.tap(
      find.descendant(of: row.first, matching: find.text('Reopen')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a project that can no longer be opened is reported and '
      'forgotten', (tester) async {
    final gone = _d('uart_bridge');
    await pumpPanel(
      tester,
      recents: [gone, _d('riscv_core')],
      missing: {gone.projectPath},
    );

    await pressReopen(tester, 'uart_bridge');

    expect(reported, hasLength(1), reason: 'the press must say why');
    expect(reported.single.$1.id, gone.id);
    expect(reported.single.$2.projectPath, gone.projectPath);
    expect(
      registry.cleared,
      [gone.id],
      reason: 'left in the list, every press fails on it the same way',
    );
    expect(find.text('uart_bridge'), findsNothing);
    expect(find.text('riscv_core'), findsOneWidget);
    expect(activations, isEmpty, reason: 'nothing was activated');
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no reporter bound, the entry is still forgotten', (
    tester,
  ) async {
    final gone = _d('uart_bridge');
    await pumpPanel(
      tester,
      recents: [gone],
      missing: {gone.projectPath},
      bindReporter: false,
    );

    await pressReopen(tester, 'uart_bridge');

    expect(registry.cleared, [gone.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a project that opens is reported as an activation once it '
      'has, though its row is gone by then', (tester) async {
    final here = _d('riscv_core');
    await pumpPanel(tester, recents: [here]);

    await pressReopen(tester, 'riscv_core');

    expect(registry.opened, [here.projectPath]);
    expect(find.text('riscv_core'), findsNothing);
    expect(activations, hasLength(1));
    expect(activations.single.source, ProjectActivationSource.recentsPanel);
    expect(activations.single.projectPath, here.projectPath);
    expect(activations.single.openProjectCount, 0);
    expect(reported, isEmpty);
    expect(registry.cleared, isEmpty);
  });
}

final _t = DateTime.utc(2026, 7, 30);

ProjectDescriptor _d(String name) => ProjectDescriptor(
  id: 'id-$name',
  displayName: name,
  projectPath: '/p/$name',
  loadedAt: _t,
  lastAccessedAt: _t,
);

/// A registry that publishes every change, as a persistent one does, and
/// refuses to open a path in [missing] the way one refuses a path that is no
/// longer on disk: it throws and keeps the entry.
class _ReactiveRegistry implements ProjectRegistry {
  _ReactiveRegistry(List<ProjectDescriptor> recents, {required this.missing})
    : _workspace = ProjectWorkspace(recentProjects: recents);

  final Set<String> missing;
  final List<String> opened = <String>[];
  final List<String> cleared = <String>[];
  final _controller = StreamController<ProjectWorkspace>.broadcast();
  ProjectWorkspace _workspace;

  void _publish(ProjectWorkspace workspace) {
    _workspace = workspace;
    _controller.add(workspace);
  }

  @override
  ProjectWorkspace get current => _workspace;

  @override
  Stream<ProjectWorkspace> watch() async* {
    yield _workspace;
    yield* _controller.stream;
  }

  @override
  Future<ProjectDescriptor> openProject(String projectPath) async {
    if (missing.contains(projectPath)) {
      throw ProjectLoadException(projectPath, 'path does not exist');
    }
    final d = _workspace.recentProjects.firstWhere(
      (r) => r.projectPath == projectPath,
    );
    opened.add(projectPath);
    _publish(
      ProjectWorkspace(
        openProjects: [..._workspace.openProjects, d],
        activeProjectId: d.id,
        recentProjects: [
          for (final r in _workspace.recentProjects)
            if (r.id != d.id) r,
        ],
      ),
    );
    return d;
  }

  @override
  Future<void> clearRecentProject(String projectId) async {
    cleared.add(projectId);
    _publish(
      _workspace.copyWith(
        recentProjects: [
          for (final r in _workspace.recentProjects)
            if (r.id != projectId) r,
        ],
      ),
    );
  }

  void dispose() => _controller.close();

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
