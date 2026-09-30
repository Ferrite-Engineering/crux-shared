// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects_ui/crux_projects_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// The seam that stops a host losing instrumentation by adopting this package.
///
/// Without it, migrating a forked switcher onto these widgets silently deletes
/// whatever the fork was recording — which is exactly what nearly happened to
/// SimCrux's catalogued `project.switched` event in 2026-08, with two tests and
/// a catalog-conformance entry behind it and not one of them failing.
void main() {
  group('projectActivationObserverProvider', () {
    test('defaults to a no-op so a host that wants nothing pays nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final observer = container.read(projectActivationObserverProvider);
      // Must not throw.
      observer(
        const ProjectActivation(
          source: ProjectActivationSource.switcher,
          projectPath: '/tmp/a',
          openProjectCount: 1,
        ),
      );
    });
  });

  group('reportProjectActivation', () {
    testWidgets('forwards the activation to the host observer', (tester) async {
      final seen = <ProjectActivation>[];
      late WidgetRef captured;

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            projectActivationObserverProvider.overrideWithValue(seen.add),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      reportProjectActivation(
        captured,
        source: ProjectActivationSource.recentsPanel,
        projectPath: '/w/proj',
        openProjectCount: 3,
        projectId: 'p1',
      );

      expect(seen, hasLength(1));
      expect(seen.single.source, ProjectActivationSource.recentsPanel);
      expect(seen.single.projectPath, '/w/proj');
      expect(seen.single.openProjectCount, 3);
      expect(seen.single.projectId, 'p1');
    });

    testWidgets('a throwing observer never breaks the interaction', (
      tester,
    ) async {
      // Instrumentation must not be able to prevent a project from switching.
      // A host with a misconfigured telemetry sink still gets its switch.
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            projectActivationObserverProvider.overrideWithValue(
              (_) => throw StateError('sink down'),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(
        () => reportProjectActivation(
          captured,
          source: ProjectActivationSource.switcher,
          projectPath: '/w/proj',
          openProjectCount: 1,
        ),
        returnsNormally,
      );
    });
  });

  group('ProjectActivationSource', () {
    test('distinguishes the three affordances', () {
      // A host that collapses these cannot tell whether its recents list is
      // earning its place, which is the question the distinction exists for.
      expect(ProjectActivationSource.values, hasLength(3));
      expect(
        ProjectActivationSource.values.toSet(),
        <ProjectActivationSource>{
          ProjectActivationSource.switcher,
          ProjectActivationSource.switcherRecents,
          ProjectActivationSource.recentsPanel,
        },
      );
    });
  });
}
