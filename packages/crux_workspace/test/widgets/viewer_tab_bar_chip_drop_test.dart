// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Dropping a dragged tab ON another tab reorders it, in both drag modes.
//
// Whole-chip mode used to accept a same-pane drop only on the insertion slots
// between chips — 8 logical pixels wide, and invisible until a drag is already
// over one. A drop aimed at a tab hit nothing and the tab did not move, which
// reads as "reordering is broken" rather than "aim two pixels left". The two
// modes also disagreed about what accepts a drop, so this pins them together.

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'v': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['v'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_chipdrop_');
    service = WorkspaceService<String>(
      codec: const _StringCodec(),
      directoryFactory: () async => tempDir,
      logger: (_) {},
    );
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        );
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Opens three tabs, pumps a bar in [useDragHandle] mode, and drags the chip
  /// labelled [from] onto the chip labelled [onto]. Returns the resulting
  /// pane-local order.
  Future<List<String>> dragChipOntoChip(
    WidgetTester tester, {
    required bool useDragHandle,
    required String from,
    required String onto,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    for (final name in ['a', 'b', 'c']) {
      await notifier.openTab(displayName: name, payload: name);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              useDragHandle: useDragHandle,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In handle mode the drag starts on the handle icon; in whole-chip mode it
    // starts anywhere on the chip. Either way the drop lands on the target
    // chip's label, which is what a user aims at.
    final source = useDragHandle
        ? find
              .descendant(
                of: find.ancestor(
                  of: find.text(from),
                  matching: find.byType(Row),
                ),
                matching: find.byIcon(Icons.drag_indicator),
              )
              .first
        : find.text(from);

    final gesture = await tester.startGesture(tester.getCenter(source));
    if (useDragHandle) {
      // The handle is a LongPressDraggable: hold past kLongPressTimeout first.
      await tester.pump(const Duration(milliseconds: 600));
    }
    // A short move first: the drag has to clear the touch slop and start
    // before a jump to the target means anything. In whole-chip mode this
    // must come promptly — hesitating on a chip lets its own long-press
    // (the context menu) win the arena instead.
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text(onto)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = await container.read(provider.future);
    return after
        .tabsForPane(ws.activePaneId)
        .map((t) => t.displayName)
        .toList();
  }

  testWidgets(
    'whole-chip mode: dropping a tab on a later tab takes its place',
    (
      tester,
    ) async {
      expect(
        await dragChipOntoChip(
          tester,
          useDragHandle: false,
          from: 'a',
          onto: 'c',
        ),
        ['b', 'c', 'a'],
      );
    },
  );

  testWidgets('whole-chip mode: dropping a tab on an earlier tab takes its '
      'place', (tester) async {
    expect(
      await dragChipOntoChip(
        tester,
        useDragHandle: false,
        from: 'c',
        onto: 'a',
      ),
      ['c', 'a', 'b'],
    );
  });

  testWidgets('handle mode drops the same way, so the modes cannot drift', (
    tester,
  ) async {
    expect(
      await dragChipOntoChip(tester, useDragHandle: true, from: 'a', onto: 'c'),
      ['b', 'c', 'a'],
    );
  });

  testWidgets('whole-chip mode keeps its insertion slots', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'a', payload: 'a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              useDragHandle: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The slots are how "before the first" and "after the last" stay sayable.
    expect(
      find.byKey(ValueKey('tabInsertionSlot_${ws.activePaneId.value}_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('tabInsertionSlot_${ws.activePaneId.value}_1')),
      findsOneWidget,
    );
  });
}
