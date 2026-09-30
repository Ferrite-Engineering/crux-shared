// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CruxDockEntry _entry(
  String id, {
  int badgeCount = 0,
  VoidCallback? onClose,
}) => CruxDockEntry(
  id: id,
  icon: Icons.table_chart_outlined,
  label: 'label-$id',
  badgeCount: badgeCount,
  onClose: onClose,
  builder: (_) => Text('content-$id'),
);

Widget _host(Widget dock) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 800, height: 400, child: dock)),
);

void main() {
  group('CruxDock', () {
    testWidgets('renders the strip and only the active tab content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CruxDock(
            entries: [_entry('a'), _entry('b')],
            activeId: 'a',
            onSelect: (_) {},
          ),
        ),
      );
      expect(find.text('label-a'), findsOneWidget);
      expect(find.text('label-b'), findsOneWidget);
      expect(find.text('content-a'), findsOneWidget);
      // Inactive tabs are not kept alive — panel state lives in providers.
      expect(find.text('content-b'), findsNothing);
    });

    testWidgets('tapping a tab fires onSelect with its id', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _host(
          CruxDock(
            entries: [_entry('a'), _entry('b')],
            activeId: 'a',
            onSelect: (id) => selected = id,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cruxDockTab-b')));
      expect(selected, 'b');
    });

    testWidgets('an unknown activeId falls back to the first entry without '
        'writing back', (tester) async {
      // A closed on-demand tab can leave a stale persisted id; the dock must
      // render the fallback and not demand host-side cleanup.
      var selectCalls = 0;
      await tester.pumpWidget(
        _host(
          CruxDock(
            entries: [_entry('a'), _entry('b')],
            activeId: 'gone',
            onSelect: (_) => selectCalls++,
          ),
        ),
      );
      expect(find.text('content-a'), findsOneWidget);
      expect(selectCalls, 0);
    });

    group('auto-hiding strip', () {
      testWidgets('one pinned entry renders as a titled header, not a tab', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            CruxDock(entries: [_entry('solo')], onSelect: (_) {}),
          ),
        );
        expect(find.text('label-solo'), findsOneWidget);
        expect(find.byKey(const ValueKey('cruxDockTab-solo')), findsNothing);
      });

      testWidgets('a second entry turns the header into a tab strip', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [
                _entry('solo'),
                _entry('diff', onClose: () {}),
              ],
              activeId: 'solo',
              onSelect: (_) {},
            ),
          ),
        );
        expect(find.byKey(const ValueKey('cruxDockTab-solo')), findsOneWidget);
        expect(find.byKey(const ValueKey('cruxDockTab-diff')), findsOneWidget);
      });

      testWidgets('a single CLOSABLE entry still renders as a tab', (
        tester,
      ) async {
        // Header mode is for the one-pinned-surface case; a lone on-demand
        // tab still needs its × visible.
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('fsm', onClose: () {})],
              onSelect: (_) {},
            ),
          ),
        );
        expect(find.byKey(const ValueKey('cruxDockTab-fsm')), findsOneWidget);
      });
    });

    group('close affordance', () {
      testWidgets('closable entries render an × that fires onClose', (
        tester,
      ) async {
        var closed = false;
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [
                _entry('a'),
                _entry('fsm', onClose: () => closed = true),
              ],
              activeId: 'fsm',
              onSelect: (_) {},
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('cruxDockClose-fsm')));
        expect(closed, isTrue);
      });

      testWidgets('pinned entries render no ×', (tester) async {
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('a'), _entry('b')],
              activeId: 'a',
              onSelect: (_) {},
            ),
          ),
        );
        expect(find.byKey(const ValueKey('cruxDockClose-a')), findsNothing);
        expect(find.byKey(const ValueKey('cruxDockClose-b')), findsNothing);
      });
    });

    group('badges', () {
      testWidgets('a non-zero badgeCount renders a count badge', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('a', badgeCount: 42), _entry('b')],
              activeId: 'a',
              onSelect: (_) {},
            ),
          ),
        );
        expect(find.text('42'), findsOneWidget);
      });

      testWidgets('zero is suppressed', (tester) async {
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('a'), _entry('b')],
              activeId: 'a',
              onSelect: (_) {},
            ),
          ),
        );
        expect(find.byType(Badge), findsNothing);
      });
    });

    group('action cluster', () {
      testWidgets('collapse fires onCollapse', (tester) async {
        var collapsed = false;
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('a')],
              onSelect: (_) {},
              onCollapse: () => collapsed = true,
              collapseTooltip: 'Collapse',
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('cruxDockCollapse')));
        expect(collapsed, isTrue);
      });

      testWidgets('maximize toggles glyph with isMaximized', (tester) async {
        var maximized = false;
        Widget build() => _host(
          CruxDock(
            entries: [_entry('a')],
            onSelect: (_) {},
            onMaximize: () => maximized = !maximized,
            isMaximized: maximized,
            maximizeTooltip: 'Maximize',
            restoreTooltip: 'Restore',
          ),
        );
        await tester.pumpWidget(build());
        expect(find.byIcon(Icons.open_in_full), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('cruxDockMaximize')));
        await tester.pumpWidget(build());
        expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);
      });

      testWidgets('omits buttons whose callbacks are absent', (tester) async {
        await tester.pumpWidget(
          _host(CruxDock(entries: [_entry('a')], onSelect: (_) {})),
        );
        expect(find.byKey(const ValueKey('cruxDockCollapse')), findsNothing);
        expect(find.byKey(const ValueKey('cruxDockMaximize')), findsNothing);
        expect(find.byKey(const ValueKey('cruxDockPopOut')), findsNothing);
      });
    });

    group('entry actions', () {
      testWidgets("renders only the ACTIVE entry's actions in the cluster", (
        tester,
      ) async {
        Widget build(String activeId) => _host(
          CruxDock(
            entries: [
              CruxDockEntry(
                id: 'stage',
                icon: Icons.dashboard_customize_outlined,
                label: 'Stage',
                actions: const [Icon(Icons.add, key: Key('stage-add'))],
                builder: (_) => const Text('stage-content'),
              ),
              _entry('b'),
            ],
            activeId: activeId,
            onSelect: (_) {},
          ),
        );
        await tester.pumpWidget(build('stage'));
        expect(find.byKey(const Key('stage-add')), findsOneWidget);
        // Another tab activates → the view-specific action disappears.
        await tester.pumpWidget(build('b'));
        expect(find.byKey(const Key('stage-add')), findsNothing);
      });
    });

    group('pop-out', () {
      testWidgets('disabled config renders an inert button with tooltip', (
        tester,
      ) async {
        // The rendered-but-disabled contract: the affordance must exist and
        // explain itself before Flutter multi-window reaches stable.
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('a')],
              onSelect: (_) {},
              popOut: const CruxDockPopOut(
                enabled: false,
                tooltip: 'Available when multi-window reaches stable',
              ),
            ),
          ),
        );
        final button = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(const ValueKey('cruxDockPopOut')),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull);
        expect(button.tooltip, 'Available when multi-window reaches stable');
      });

      testWidgets('enabled config pops out the ACTIVE tab id', (tester) async {
        String? popped;
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('a'), _entry('b')],
              activeId: 'b',
              onSelect: (_) {},
              popOut: CruxDockPopOut(
                enabled: true,
                tooltip: 'Pop out',
                onPopOut: (id) => popped = id,
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('cruxDockPopOut')));
        expect(popped, 'b');
      });
    });

    group('auto-reveal', () {
      Widget build({
        required List<CruxDockEntry> entries,
        required ValueChanged<String> onAutoReveal,
      }) => _host(
        CruxDock(
          entries: entries,
          activeId: 'a',
          onSelect: (_) {},
          onAutoReveal: onAutoReveal,
        ),
      );

      testWidgets('fires post-frame when a new closable entry appears', (
        tester,
      ) async {
        final revealed = <String>[];
        await tester.pumpWidget(
          build(entries: [_entry('a')], onAutoReveal: revealed.add),
        );
        expect(revealed, isEmpty);

        await tester.pumpWidget(
          build(
            entries: [
              _entry('a'),
              _entry('fsm', onClose: () {}),
            ],
            onAutoReveal: revealed.add,
          ),
        );
        await tester.pump();
        expect(revealed, ['fsm']);
      });

      testWidgets('never fires for the initial entry set', (tester) async {
        // Restoring a session that already has an FSM tab must not steal the
        // user's persisted active tab.
        final revealed = <String>[];
        await tester.pumpWidget(
          build(
            entries: [
              _entry('a'),
              _entry('fsm', onClose: () {}),
            ],
            onAutoReveal: revealed.add,
          ),
        );
        await tester.pump();
        expect(revealed, isEmpty);
      });

      testWidgets('never fires for a new PINNED entry', (tester) async {
        final revealed = <String>[];
        await tester.pumpWidget(
          build(entries: [_entry('a')], onAutoReveal: revealed.add),
        );
        await tester.pumpWidget(
          build(
            entries: [_entry('a'), _entry('b')],
            onAutoReveal: revealed.add,
          ),
        );
        await tester.pump();
        expect(revealed, isEmpty);
      });

      testWidgets('a re-appearing closable entry reveals again', (
        tester,
      ) async {
        // Close FSM, run the analysis again → it should re-reveal.
        final revealed = <String>[];
        await tester.pumpWidget(
          build(
            entries: [
              _entry('a'),
              _entry('fsm', onClose: () {}),
            ],
            onAutoReveal: revealed.add,
          ),
        );
        await tester.pumpWidget(
          build(entries: [_entry('a')], onAutoReveal: revealed.add),
        );
        await tester.pumpWidget(
          build(
            entries: [
              _entry('a'),
              _entry('fsm', onClose: () {}),
            ],
            onAutoReveal: revealed.add,
          ),
        );
        await tester.pump();
        expect(revealed, ['fsm']);
      });
    });

    testWidgets('strip overflows by scrolling, actions stay pinned', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: CruxDock(
                entries: [for (var i = 0; i < 12; i++) _entry('t$i')],
                activeId: 't0',
                onSelect: (_) {},
                onCollapse: () {},
                collapseTooltip: 'Collapse',
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // The collapse button remains visible despite 12 tabs at 300px.
      expect(find.byKey(const ValueKey('cruxDockCollapse')), findsOneWidget);
    });

    group('drag between docks', () {
      Widget twoDocks({
        required void Function(String, String) onMovedIntoRight,
      }) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: CruxDock(
                  dockId: 'bottom',
                  entries: [
                    _entry('a'),
                    CruxDockEntry(
                      id: 'fsm',
                      icon: Icons.account_tree_outlined,
                      label: 'FSM',
                      movable: true,
                      onClose: () {},
                      builder: (_) => const Text('content-fsm'),
                    ),
                  ],
                  activeId: 'fsm',
                  onSelect: (_) {},
                  onTabMovedIn: (_, _) {},
                ),
              ),
              Expanded(
                child: CruxDock(
                  dockId: 'right',
                  entries: [_entry('b')],
                  onSelect: (_) {},
                  onTabMovedIn: onMovedIntoRight,
                ),
              ),
            ],
          ),
        ),
      );

      testWidgets('dropping a movable tab on another dock re-homes it', (
        tester,
      ) async {
        (String, String)? moved;
        await tester.pumpWidget(
          twoDocks(onMovedIntoRight: (id, from) => moved = (id, from)),
        );

        final from = tester.getCenter(
          find.byKey(const ValueKey('cruxDockTab-fsm')),
        );
        // The second dock has one pinned entry → header mode; drop on its
        // strip (the header row hosts the DragTarget too).
        final to = tester.getCenter(find.text('label-b'));
        final gesture = await tester.startGesture(from);
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(to);
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(moved, ('fsm', 'bottom'));
      });

      testWidgets('a drop back onto the source dock is rejected', (
        tester,
      ) async {
        (String, String)? moved;
        await tester.pumpWidget(
          twoDocks(onMovedIntoRight: (id, from) => moved = (id, from)),
        );
        final from = tester.getCenter(
          find.byKey(const ValueKey('cruxDockTab-fsm')),
        );
        final gesture = await tester.startGesture(from);
        await tester.pump(const Duration(milliseconds: 600));
        // Drop on the SAME dock's strip (over the pinned neighbour tab).
        await gesture.moveTo(
          tester.getCenter(find.byKey(const ValueKey('cruxDockTab-a'))),
        );
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(moved, isNull);
      });

      testWidgets('non-movable tabs do not drag', (tester) async {
        await tester.pumpWidget(
          twoDocks(onMovedIntoRight: (_, _) {}),
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('cruxDockTab-a')),
            matching: find.byType(Draggable<CruxDockDragData>),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('cruxDockTab-fsm')),
            matching: find.byType(Draggable<CruxDockDragData>),
          ),
          findsOneWidget,
        );
      });
    });

    group('narrow-strip resilience', () {
      // The action cluster used to take its natural width unconditionally, so
      // a dock dragged narrower than the cluster overflowed the strip Row
      // (RenderFlex overflow during splitter resizes). The cluster is now
      // capped and scrolls, shedding the active tab's view actions from the
      // left while the standard actions stay pinned at the right edge.
      Widget narrowHost(double width, {required VoidCallback onCollapse}) {
        final actionsEntry = CruxDockEntry(
          id: 'a',
          icon: Icons.table_chart_outlined,
          label: 'label-a',
          builder: (_) => const Text('content-a'),
          actions: [
            for (var i = 0; i < 8; i++)
              IconButton(
                key: ValueKey('busy-action-$i'),
                icon: const Icon(Icons.circle, size: kCruxDockIconSize),
                onPressed: () {},
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
              ),
          ],
        );
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 400,
              child: CruxDock(
                entries: [actionsEntry, _entry('b')],
                activeId: 'a',
                onSelect: (_) {},
                onCollapse: onCollapse,
                onMaximize: () {},
              ),
            ),
          ),
        );
      }

      testWidgets('a strip narrower than the action cluster does not '
          'overflow', (tester) async {
        await tester.pumpWidget(narrowHost(200, onCollapse: () {}));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(narrowHost(90, onCollapse: () {}));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the standard actions stay tappable at the right edge '
          'while narrow', (tester) async {
        var collapsed = 0;
        await tester.pumpWidget(narrowHost(90, onCollapse: () => collapsed++));
        // reverse: true anchors the cluster's tail — collapse (the escape
        // hatch) must be on screen and hittable without scrolling.
        await tester.tap(find.byKey(const ValueKey('cruxDockCollapse')));
        expect(collapsed, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('shed view actions scroll back into reach', (tester) async {
        await tester.pumpWidget(narrowHost(120, onCollapse: () {}));
        // The leading view action is shed off the cluster's left edge…
        final firstAction = find.byKey(const ValueKey('busy-action-0'));
        expect(firstAction.hitTestable(), findsNothing);
        // …but a drag on the cluster's scroll view brings it back.
        final clusterScroll = find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.reverse,
        );
        expect(clusterScroll, findsOneWidget);
        await tester.drag(clusterScroll, const Offset(600, 0));
        await tester.pumpAndSettle();
        expect(firstAction.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a wide strip still gives the cluster its natural width '
          '(no scrolling, tabs keep the rest)', (tester) async {
        await tester.pumpWidget(narrowHost(800, onCollapse: () {}));
        expect(
          find.byKey(const ValueKey('busy-action-0')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('label-a'), findsOneWidget);
        expect(find.text('label-b'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('content floor (squeeze protection)', () {
      // The pane open/close animation sweeps the region size through zero,
      // and resting pane minimums can sit below a panel's natural minimum.
      // Below the floor the dock lays content out AT the floor and clips —
      // so a panel with fixed-height children can never transiently
      // RenderFlex-overflow during an open/close.
      Widget strictPanel() => Column(
        children: [
          const SizedBox(height: 100, child: Placeholder()),
          const Divider(height: 1),
          Expanded(child: Container(color: const Color(0xFF224422))),
        ],
      );

      testWidgets('content squeezed below the floor clips instead of '
          'overflowing', (tester) async {
        for (final height in [80.0, 48.0, 40.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 400,
                    height: height,
                    child: CruxDock(
                      entries: [
                        CruxDockEntry(
                          id: 'strict',
                          icon: Icons.table_chart_outlined,
                          label: 'Strict',
                          builder: (_) => strictPanel(),
                        ),
                      ],
                      activeId: 'strict',
                      onSelect: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at dock height $height',
          );
        }
      });

      testWidgets('a roomy dock lays content out at its real size', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: CruxDock(
                  entries: [
                    CruxDockEntry(
                      id: 'strict',
                      icon: Icons.table_chart_outlined,
                      label: 'Strict',
                      builder: (_) => strictPanel(),
                    ),
                  ],
                  activeId: 'strict',
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        );
        // Content region = 400 - 32 strip; the Expanded body fills the rest.
        final size = tester.getSize(find.byType(Placeholder));
        expect(size.height, 100);
        expect(tester.takeException(), isNull);
      });
    });

    group('collapse direction + restore bar', () {
      testWidgets('the hide glyph points into the collapse edge', (
        tester,
      ) async {
        for (final (direction, icon) in [
          (CruxDockCollapseDirection.down, Icons.keyboard_double_arrow_down),
          (CruxDockCollapseDirection.left, Icons.keyboard_double_arrow_left),
          (
            CruxDockCollapseDirection.right,
            Icons.keyboard_double_arrow_right,
          ),
        ]) {
          await tester.pumpWidget(
            _host(
              CruxDock(
                entries: [_entry('a')],
                onSelect: (_) {},
                onCollapse: () {},
                collapseTooltip: 'Hide',
                collapseDirection: direction,
              ),
            ),
          );
          expect(
            find.byIcon(icon),
            findsOneWidget,
            reason: 'glyph for $direction',
          );
        }
      });

      testWidgets('a restore bar lists the collapsed tabs and a tap '
          'restores that tab', (tester) async {
        String? restored;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CruxDockRestoreBar(
                edge: CruxDockCollapseDirection.right,
                entries: [
                  CruxDockRestoreEntry(
                    id: 'values',
                    icon: Icons.data_array,
                    label: 'Values',
                    onRestore: () => restored = 'values',
                  ),
                  CruxDockRestoreEntry(
                    id: 'crossProbe',
                    icon: Icons.sensors_outlined,
                    label: 'Cross-Probe',
                    onRestore: () => restored = 'crossProbe',
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('cruxDockRestore-values')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('cruxDockRestore-crossProbe')),
        );
        expect(restored, 'crossProbe');
        // Vertical bar for a side edge.
        final size = tester.getSize(find.byType(CruxDockRestoreBar));
        expect(size.width, kCruxDockRestoreBarThickness);
      });
    });

    testWidgets('renders under a dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: CruxDock(
              entries: [
                _entry('a'),
                _entry('b', onClose: () {}),
              ],
              activeId: 'a',
              onSelect: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('label-a'), findsOneWidget);
    });
  });
}
