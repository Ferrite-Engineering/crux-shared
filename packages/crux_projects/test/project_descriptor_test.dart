// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectDescriptor', () {
    final t = DateTime.utc(2026, 3, 1, 12);

    ProjectDescriptor make({
      String id = 'project_test',
      String displayName = 'demo.proj',
      String projectPath = '/projects/demo/demo.proj',
      DateTime? loadedAt,
      DateTime? lastAccessedAt,
      bool isPinned = false,
    }) {
      return ProjectDescriptor(
        id: id,
        displayName: displayName,
        projectPath: projectPath,
        loadedAt: loadedAt ?? t,
        lastAccessedAt: lastAccessedAt ?? t,
        isPinned: isPinned,
      );
    }

    test('equality is value-based', () {
      expect(make(), make());
      expect(make(), isNot(make(displayName: 'other')));
      expect(make(), isNot(make(isPinned: true)));
    });

    test('copyWith overrides individual fields', () {
      final a = make();
      final b = a.copyWith(isPinned: true, displayName: 'renamed');
      expect(b.isPinned, isTrue);
      expect(b.displayName, 'renamed');
      expect(b.id, a.id);
      expect(b.projectPath, a.projectPath);
    });

    test('idForPath is stable, deterministic, and path-dependent', () {
      final a1 = ProjectDescriptor.idForPath('/a/proj/x.proj');
      final a2 = ProjectDescriptor.idForPath('/a/proj/x.proj');
      final b = ProjectDescriptor.idForPath('/b/proj/x.proj');
      expect(a1, a2);
      expect(a1, isNot(b));
      expect(a1, startsWith('project_'));
    });

    test('idForPath format is a stable on-disk contract', () {
      // The id is persisted in workspace.json across restarts; changing the
      // hash algorithm would orphan every existing per-project scope. This
      // pins the exact format (prefix + 16 lowercase hex digits).
      final id = ProjectDescriptor.idForPath('/projects/demo/demo.proj');
      expect(id, matches(RegExp(r'^project_[0-9a-f]{16}$')));
    });

    test('round-trips through JSON preserving every field', () {
      final original = make(isPinned: true);
      final parsed = ProjectDescriptor.fromJson(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed, original);
    });

    test('toJson uses the stable snake_case key contract', () {
      final json = make(isPinned: true).toJson();
      expect(json.keys, <String>{
        'id',
        'display_name',
        'project_path',
        'loaded_at',
        'last_accessed_at',
        'is_pinned',
      });
    });

    test('fromJson tolerates missing optional fields', () {
      final parsed = ProjectDescriptor.fromJson(<String, Object?>{
        'id': 'x',
        'display_name': 'x.proj',
        'project_path': '/x.proj',
      });
      expect(parsed, isNotNull);
      expect(parsed!.isPinned, isFalse);
    });

    test('fromJson silently ignores unknown keys', () {
      final parsed = ProjectDescriptor.fromJson(<String, Object?>{
        'id': 'x',
        'display_name': 'x.proj',
        'project_path': '/x.proj',
        'unknown_future_field': 'whatever',
      });
      expect(parsed, isNotNull);
    });

    test('fromJson rejects missing required fields', () {
      expect(
        ProjectDescriptor.fromJson(<String, Object?>{
          'id': 'x',
          // missing display_name
          'project_path': '/x.proj',
        }),
        isNull,
      );
      expect(ProjectDescriptor.fromJson(null), isNull);
      expect(ProjectDescriptor.fromJson('not a map'), isNull);
    });
  });
}
