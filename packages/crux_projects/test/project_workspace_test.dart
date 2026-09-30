// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectWorkspace', () {
    final t = DateTime.utc(2026, 3, 1, 12);

    ProjectDescriptor desc(String id, {bool pinned = false}) =>
        ProjectDescriptor(
          id: id,
          displayName: '$id.proj',
          projectPath: '/projects/$id.proj',
          loadedAt: t,
          lastAccessedAt: t,
          isPinned: pinned,
        );

    test('empty workspace is the default', () {
      final ws = ProjectWorkspace.empty();
      expect(ws.openProjects, isEmpty);
      expect(ws.recentProjects, isEmpty);
      expect(ws.activeProjectId, isNull);
      expect(ws.isEmpty, isTrue);
      expect(ws.openCount, 0);
    });

    test('activeProject resolves to a member of openProjects', () {
      final a = desc('a');
      final b = desc('b');
      final ws = ProjectWorkspace(
        openProjects: <ProjectDescriptor>[a, b],
        activeProjectId: 'b',
      );
      expect(ws.activeProject, b);
    });

    test('activeProject is null when id does not match any open project', () {
      final ws = ProjectWorkspace(
        openProjects: <ProjectDescriptor>[desc('a')],
        activeProjectId: 'bogus',
      );
      expect(ws.activeProject, isNull);
    });

    test('recentProjects is capped at the model constant', () {
      final many = List<ProjectDescriptor>.generate(
        ProjectWorkspace.recentProjectsCap + 5,
        (i) => desc('p$i'),
      );
      final ws = ProjectWorkspace(recentProjects: many);
      expect(ws.recentProjects, hasLength(ProjectWorkspace.recentProjectsCap));
    });

    test(
      'copyWith preserves and overrides fields; clearActive nulls active',
      () {
        final a = desc('a');
        final ws = ProjectWorkspace(
          openProjects: <ProjectDescriptor>[a],
          activeProjectId: 'a',
        );
        final ws2 = ws.copyWith(clearActive: true);
        expect(ws2.activeProjectId, isNull);
        expect(ws2.openProjects, ws.openProjects);
      },
    );

    test('round-trips through JSON preserving open/active/recent', () {
      final a = desc('a');
      final b = desc('b', pinned: true);
      final original = ProjectWorkspace(
        openProjects: <ProjectDescriptor>[a, b],
        activeProjectId: 'b',
        recentProjects: <ProjectDescriptor>[desc('r1')],
      );
      final parsed = ProjectWorkspace.fromJson(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed, original);
    });

    test('fromJson clamps active id to an actually-open project', () {
      final parsed = ProjectWorkspace.fromJson(<String, Object?>{
        'version': 1,
        'open_projects': <Object>[desc('a').toJson()],
        'active_project_id': 'b',
        'recent_projects': <Object>[],
      });
      expect(parsed, isNotNull);
      expect(parsed!.activeProjectId, isNull);
    });

    test('fromJson returns null on future major version', () {
      expect(
        ProjectWorkspace.fromJson(<String, Object?>{'version': 99}),
        isNull,
      );
    });

    test('fromJson is tolerant of malformed input', () {
      expect(ProjectWorkspace.fromJson(null), isNull);
      expect(ProjectWorkspace.fromJson('not a map'), isNull);
      expect(ProjectWorkspace.fromJson(<String, Object?>{}), isNotNull);
    });
  });
}
