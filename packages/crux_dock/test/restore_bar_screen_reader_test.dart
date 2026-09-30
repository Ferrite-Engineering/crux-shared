// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each restore button is a named button inside its region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final restored = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: CruxDockRestoreBar(
              edge: CruxDockCollapseDirection.down,
              semanticsLabel: 'Panel dock',
              entries: <CruxDockRestoreEntry>[
                CruxDockRestoreEntry(
                  id: 'tx',
                  icon: Icons.table_rows,
                  label: 'Transactions',
                  onRestore: () => restored.add('tx'),
                ),
                CruxDockRestoreEntry(
                  id: 'stage',
                  icon: Icons.animation,
                  label: 'Stage',
                  onRestore: () => restored.add('stage'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(walk.stops.map((s) => s.line), <String>[
      '[Panel dock grouping] Transactions button',
      'Stage button',
    ]);
    handle.dispose();
  });
}
