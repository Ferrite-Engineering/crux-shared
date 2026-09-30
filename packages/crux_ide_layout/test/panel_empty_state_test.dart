// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('renders the muted centered message', (tester) async {
    await _pump(tester, const CruxPanelEmptyState(message: 'Nothing here'));
    final text = tester.widget<Text>(find.text('Nothing here'));
    final context = tester.element(find.text('Nothing here'));
    expect(text.textAlign, TextAlign.center);
    expect(
      text.style?.color,
      Theme.of(context).colorScheme.onSurfaceVariant,
    );
    expect(find.byIcon(Icons.inbox_outlined), findsNothing);
  });

  testWidgets('optional icon and action render around the message', (
    tester,
  ) async {
    var tapped = false;
    await _pump(
      tester,
      CruxPanelEmptyState(
        message: 'Nothing here',
        icon: Icons.inbox_outlined,
        action: OutlinedButton(
          onPressed: () => tapped = true,
          child: const Text('Open…'),
        ),
      ),
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    await tester.tap(find.text('Open…'));
    expect(tapped, isTrue);
  });

  // ── Squeezed regions ──────────────────────────────────────────────────────
  //
  // A dock the user drags up, or a pane collapsed toward its floor, can leave
  // a panel far shorter than this stack's natural height. A bare `Center` +
  // `Column` overflows there and clips from the bottom — taking the [action]
  // with it. WaveCrux shipped exactly that: `RenderFlex overflowed by 11
  // pixels` in a 53 px dock region (integration run 30591309796). In release
  // there is no debug stripe, so the call to action simply vanishes.
  testWidgets('does not overflow when the region is far shorter than the '
      'content, and the action stays reachable', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      // 40 px against a stack whose natural height is well over 100.
      SizedBox(
        height: 40,
        child: CruxPanelEmptyState(
          message: 'Nothing here',
          icon: Icons.inbox_outlined,
          action: OutlinedButton(
            onPressed: () => tapped = true,
            child: const Text('Open…'),
          ),
        ),
      ),
    );

    // No RenderFlex overflow was thrown during layout.
    expect(tester.takeException(), isNull);

    // The action is still there and still usable — scrolled to, not clipped
    // away. `ensureVisible` is the whole point: it would fail if the button
    // had been clipped by a non-scrollable parent.
    await tester.ensureVisible(find.text('Open…'));
    await tester.pump();
    await tester.tap(find.text('Open…'));
    expect(tapped, isTrue);
  });

  testWidgets('stays inert at a comfortable height (nothing to scroll)', (
    tester,
  ) async {
    await _pump(
      tester,
      const SizedBox(
        height: 600,
        child: CruxPanelEmptyState(
          message: 'Nothing here',
          icon: Icons.inbox_outlined,
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // `minHeight: constraints.maxHeight` makes the content exactly fill the
    // viewport, so the scroll view has no extent to travel. If this regresses,
    // panels would gain a stray scrollbar and drag-scroll at normal sizes.
    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
    expect(scrollable.controller?.position.maxScrollExtent ?? 0, 0);
  });

  testWidgets('centres content when the region is unbounded', (tester) async {
    await _pump(
      tester,
      // A column gives its child unbounded height; the guard must fall back to
      // a plain Center rather than build a scroll view with no viewport.
      const Column(
        children: [CruxPanelEmptyState(message: 'Nothing here')],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing here'), findsOneWidget);
  });
}
