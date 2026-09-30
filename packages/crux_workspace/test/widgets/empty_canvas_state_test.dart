// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyCanvasState', () {
    testWidgets('renders the title and subtitle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            title: 'Welcome to TestCrux',
            subtitle: 'Open a netlist to begin.',
          ),
        ),
      );
      expect(find.text('Welcome to TestCrux'), findsOneWidget);
      expect(find.text('Open a netlist to begin.'), findsOneWidget);
    });

    testWidgets('omits subtitle when null', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyCanvasState(title: 'Only title')),
      );
      expect(find.text('Only title'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('renders versionLabel under the subtitle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            title: 'Welcome to TestCrux',
            subtitle: 'Open a netlist to begin.',
            versionLabel: 'Version 0.5.0',
          ),
        ),
      );
      expect(find.text('Version 0.5.0'), findsOneWidget);
      expect(find.byKey(const Key('empty_canvas_version')), findsOneWidget);

      // Ordering matters: the version is the muted line *below* the subtitle,
      // not a second headline above it.
      final subtitleY = tester
          .getTopLeft(find.text('Open a netlist to begin.'))
          .dy;
      final versionY = tester.getTopLeft(find.text('Version 0.5.0')).dy;
      expect(versionY, greaterThan(subtitleY));
    });

    testWidgets('omits versionLabel when null', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyCanvasState(title: 'Only title')),
      );
      expect(find.byKey(const Key('empty_canvas_version')), findsNothing);
    });

    testWidgets('renders versionLabel without a subtitle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(title: 't', versionLabel: 'Version 0.5.0'),
        ),
      );
      expect(find.byKey(const Key('empty_canvas_version')), findsOneWidget);
    });

    testWidgets('ignores versionLabel when children is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            title: 't',
            versionLabel: 'Version 0.5.0',
            children: [Text('custom-body')],
          ),
        ),
      );
      expect(find.text('custom-body'), findsOneWidget);
      expect(find.byKey(const Key('empty_canvas_version')), findsNothing);
    });

    testWidgets('renders recentFilesSection when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            title: 't',
            recentFilesSection: Text('recent-files'),
          ),
        ),
      );
      expect(find.text('recent-files'), findsOneWidget);
    });

    testWidgets('hides recentFilesSection when null', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyCanvasState(title: 't')));
      expect(find.text('recent-files'), findsNothing);
    });

    testWidgets('renders recentWorkspacesSection when provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            title: 't',
            recentWorkspacesSection: Text('recent-workspaces'),
          ),
        ),
      );
      expect(find.text('recent-workspaces'), findsOneWidget);
    });

    testWidgets('renders primaryActions in a Wrap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EmptyCanvasState(
            title: 't',
            primaryActions: [
              FilledButton(onPressed: () {}, child: const Text('Open File')),
              OutlinedButton(onPressed: () {}, child: const Text('New Tab')),
            ],
          ),
        ),
      );
      expect(find.text('Open File'), findsOneWidget);
      expect(find.text('New Tab'), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
    });

    testWidgets('renders without overflow at phone width (320 × 568)', (
      tester,
    ) async {
      // 320 × 568 is the smallest valid iPhone 5/SE scene; the widget must
      // collapse padding and stay within bounds.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          EmptyCanvasState(
            title: 'Title',
            subtitle: 'Subtitle goes here',
            recentFilesSection: const Text('files'),
            primaryActions: [
              FilledButton(onPressed: () {}, child: const Text('Action')),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('renders without overflow at tablet width (900 × 1200)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          EmptyCanvasState(
            title: 'Title',
            primaryActions: [
              FilledButton(onPressed: () {}, child: const Text('Action')),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty primaryActions hides the action row', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyCanvasState(title: 't')));
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('children slot replaces the convenience composition', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            // title is ignored when children is supplied.
            title: 'ignored-title',
            children: [Text('custom-header'), Text('custom-body')],
          ),
        ),
      );
      expect(find.text('custom-header'), findsOneWidget);
      expect(find.text('custom-body'), findsOneWidget);
      expect(find.text('ignored-title'), findsNothing);
    });

    testWidgets('children slot preserves declared order', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            children: [Text('first'), Text('second'), Text('third')],
          ),
        ),
      );
      final first = tester.getTopLeft(find.text('first')).dy;
      final second = tester.getTopLeft(find.text('second')).dy;
      final third = tester.getTopLeft(find.text('third')).dy;
      expect(first, lessThan(second));
      expect(second, lessThan(third));
    });

    testWidgets('useCard:false renders without a Card wrapper', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyCanvasState(
            useCard: false,
            children: [Text('flat')],
          ),
        ),
      );
      expect(find.text('flat'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('useCard defaults to true (Card present)', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyCanvasState(children: [Text('boxed')])),
      );
      expect(find.byType(Card), findsOneWidget);
    });
  });
}
