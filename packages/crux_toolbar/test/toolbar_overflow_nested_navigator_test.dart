// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overflow popup opens under its button when the button sits in a nested
/// navigator below a strip, as a tab's content does. The menu's position is
/// measured against the root overlay, so it must be laid out in that overlay
/// too; a nested navigator's overlay has a different origin.
void main() {
  testWidgets(
    'the overflow popup opens under its button in a nested navigator',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Column(
            children: <Widget>[
              const SizedBox(height: 90),
              Expanded(child: child!),
            ],
          ),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: 85),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (context) => Material(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: CruxToolbarOverflowMenu<String>(
                            groups: const <CruxOverflowGroup<String>>[
                              CruxOverflowGroup<String>(
                                label: 'File',
                                actions: <String>['Open'],
                              ),
                            ],
                            labelOf: (a) => a,
                            isEnabled: (_) => true,
                            shortcutOf: (_) => null,
                            onAction: (_) {},
                            tooltip: 'More',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final button = tester.getRect(
        find.byType(CruxToolbarOverflowMenu<String>),
      );

      await tester.tap(find.byType(CruxToolbarOverflowMenu<String>));
      await tester.pumpAndSettle();

      final menu = tester.getRect(
        find
            .ancestor(of: find.text('Open'), matching: find.byType(Material))
            .first,
      );
      expect((menu.top - button.top).abs(), lessThan(4));
    },
  );
}
