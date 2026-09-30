// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The auto-hiding scroll chevrons' listener lifecycle.
///
/// Three defects converged in this one code path:
///
/// * `build()` scheduled an `addPostFrameCallback` on every rebuild. The
///   enclosing `DragTarget` rebuilds continuously during a tab drag, so that
///   was one closure allocation and one scheduled callback *per frame*.
/// * `_updateScrollFlags` called `setState` with no `mounted` check, despite
///   being reachable from a post-frame callback that can outlive the element.
/// * There was no `didUpdateWidget`, so flipping `autoHideScrollChevrons`
///   false -> true on a live element never attached the scroll listener and
///   the chevrons stayed hidden forever.

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'value': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['value'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_scroll_');
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

  /// Pumps a bar inside a narrow viewport so the tab strip genuinely
  /// overflows and the chevrons have something to report.
  Future<ProviderContainer> pumpBar(
    WidgetTester tester, {
    required bool autoHide,
    required int tabCount,
    double width = 200,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    for (var i = 0; i < tabCount; i++) {
      await notifier.openTab(
        displayName: 'A rather long tab title $i',
        payload: 'p$i',
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: _Harness(
                  paneId: ws.activePaneId,
                  provider: provider,
                  autoHide: autoHide,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('autoHide false renders both chevrons unconditionally', (
    tester,
  ) async {
    await pumpBar(tester, autoHide: false, tabCount: 1, width: 600);

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('autoHide hides the chevrons when the strip fits', (
    tester,
  ) async {
    await pumpBar(tester, autoHide: true, tabCount: 1, width: 600);

    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('autoHide shows the right chevron when the strip overflows', (
    tester,
  ) async {
    await pumpBar(tester, autoHide: true, tabCount: 6);

    expect(
      find.byIcon(Icons.chevron_right),
      findsOneWidget,
      reason: 'the post-frame probe must seed the flags after first layout',
    );
    expect(
      find.byIcon(Icons.chevron_left),
      findsNothing,
      reason: 'nothing is scrolled off to the left yet',
    );
  });

  testWidgets('scrolling updates the flags through the listener', (
    tester,
  ) async {
    await pumpBar(tester, autoHide: true, tabCount: 6);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.chevron_left),
      findsOneWidget,
      reason: 'the scroll listener must keep the flags live',
    );
  });

  testWidgets(
    'flipping autoHideScrollChevrons false -> true on a LIVE element '
    'attaches the listener',
    (tester) async {
      // The regression: initState had already run with autoHide == false, and
      // without didUpdateWidget nothing ever attached the listener, so the
      // chevrons could never appear no matter how far the strip overflowed.
      await pumpBar(tester, autoHide: false, tabCount: 6);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      tester
          .state<_HarnessState>(find.byType(_Harness))
          .setAutoHide(value: true);
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.chevron_right),
        findsOneWidget,
        reason:
            'the strip overflows, so the right chevron stays visible — '
            'and it can only know that if the listener got attached',
      );

      // Scrolling must now be observed, which is only possible with a live
      // listener.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    },
  );

  testWidgets('flipping true -> false restores unconditional chevrons', (
    tester,
  ) async {
    await pumpBar(tester, autoHide: true, tabCount: 1, width: 600);
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    tester
        .state<_HarnessState>(find.byType(_Harness))
        .setAutoHide(value: false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('unmounting mid-scroll does not throw a setState-after-dispose', (
    tester,
  ) async {
    final container = await pumpBar(tester, autoHide: true, tabCount: 6);

    // Start a fling so a scroll notification is in flight, then tear the
    // widget down before it settles.
    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(-300, 0),
      1000,
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container, isNotNull);
  });

  testWidgets('adding a tab re-probes the scroll flags', (tester) async {
    // The build-time post-frame callback that was deleted did cover this
    // case incidentally. The replacement is a bounded re-probe on a tab-set
    // change, so the chevrons must still react to a tab being opened.
    final container = await pumpBar(
      tester,
      autoHide: true,
      tabCount: 1,
      width: 260,
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    for (var i = 0; i < 5; i++) {
      await container
          .read(provider.notifier)
          .openTab(displayName: 'Another long tab title $i', payload: 'x$i');
    }
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.chevron_right),
      findsOneWidget,
      reason: 'opening tabs changes maxScrollExtent without a scroll event',
    );
  });
}

/// Lets a test flip `autoHideScrollChevrons` on an already-mounted bar.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.paneId,
    required this.provider,
    required this.autoHide,
  });

  final PaneId paneId;
  final AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  final bool autoHide;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late bool _autoHide = widget.autoHide;

  void setAutoHide({required bool value}) => setState(() => _autoHide = value);

  @override
  Widget build(BuildContext context) => ViewerTabBar<String>(
    paneId: widget.paneId,
    provider: widget.provider,
    autoHideScrollChevrons: _autoHide,
  );
}
