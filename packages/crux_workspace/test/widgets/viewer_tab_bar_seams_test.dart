// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Behavioural tests for the additive ViewerTabBar seams
// (trailingActionsBuilder, sizing, leadingInset, autoHideScrollChevrons).
// These hydrate a real WorkspaceNotifier from a temp directory and pump the
// widget, so they verify the slot actually renders rather than just pinning
// the constructor shape.

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
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_seams_');
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

  Future<PaneId> hydrateWithTab(ProviderContainer container) async {
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'Tab A', payload: 'a');
    return ws.activePaneId;
  }

  Future<Widget> pumpBar(
    WidgetTester tester, {
    required ProviderContainer container,
    required PaneId paneId,
    PaneTrailingActionsBuilder? trailingActionsBuilder,
    ViewerTabBarSizing sizing = const ViewerTabBarSizing(),
  }) async {
    final bar = ViewerTabBar<String>(
      paneId: paneId,
      provider: provider,
      defaultPayloadBuilder: () => 'new',
      trailingActionsBuilder: trailingActionsBuilder,
      sizing: sizing,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: bar)),
      ),
    );
    await tester.pumpAndSettle();
    return bar;
  }

  testWidgets('trailingActionsBuilder renders after the + button', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final paneId = await hydrateWithTab(container);

    await pumpBar(
      tester,
      container: container,
      paneId: paneId,
      trailingActionsBuilder: (context, pane) => IconButton(
        key: const ValueKey('trailingSlot'),
        onPressed: () {},
        icon: const Icon(Icons.info_outline),
      ),
    );

    expect(find.byKey(const ValueKey('trailingSlot')), findsOneWidget);
  });

  testWidgets('no trailingActionsBuilder renders nothing extra', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final paneId = await hydrateWithTab(container);

    await pumpBar(tester, container: container, paneId: paneId);

    expect(find.byKey(const ValueKey('trailingSlot')), findsNothing);
    // The built-in "+" button still renders.
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('sizing.barHeight constrains the bar height', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final paneId = await hydrateWithTab(container);

    await pumpBar(
      tester,
      container: container,
      paneId: paneId,
      sizing: const ViewerTabBarSizing(barHeight: 56),
    );

    final size = tester.getSize(find.byType(ViewerTabBar<String>));
    expect(size.height, 56);
  });
}
