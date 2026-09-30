// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// PaneHost public-surface tests. Widget-level integration tests (split-pane
// rendering, active-pane indicator, drag-to-pane wiring) are deferred to a
// follow-on batch — the harness-level Riverpod-3.x container/widget interop
// has a timing quirk shared with ViewerTabBar's deferred widget tests; both
// will land together. The static structure pinned here protects the public
// surface from accidental constructor regressions.

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
  group('PaneHost public surface', () {
    late Directory tempDir;
    late WorkspaceService<String> service;
    late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
    provider;
    late ProviderContainer root;
    late TabContainerManager tabsManager;
    late PaneContainerManager panesManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('crux_pane_host_');
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
      root = ProviderContainer();
      tabsManager = TabContainerManager(rootContainer: root);
      panesManager = PaneContainerManager(rootContainer: root);
    });

    tearDown(() async {
      tabsManager.dispose();
      panesManager.dispose();
      root.dispose();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('constructor accepts every documented parameter', () {
      final host = PaneHost<String>(
        provider: provider,
        tabContentBuilder: (ctx, tab) => Text(tab.displayName),
        tabs: tabsManager,
        panes: panesManager,
        emptyCanvasContent: const Text('empty'),
        defaultPayloadBuilder: () => 'default',
        enableSplitPane: false,
      );
      expect(host.provider, equals(provider));
      expect(host.tabs, same(tabsManager));
      expect(host.panes, same(panesManager));
      expect(host.defaultPayloadBuilder, isNotNull);
      expect(host.enableSplitPane, isFalse);
      expect(host.emptyCanvasContent, isA<Text>());
      expect(host.strings, isA<ViewerTabBarStringsEn>());
    });

    test('enableSplitPane defaults to true', () {
      final host = PaneHost<String>(
        provider: provider,
        tabContentBuilder: (_, _) => const SizedBox(),
        tabs: tabsManager,
        panes: panesManager,
        emptyCanvasContent: const SizedBox(),
      );
      expect(host.enableSplitPane, isTrue);
    });

    test('PaneHost accepts a TabContentBuilder lambda', () {
      // The constructor test above already exercises the typedef
      // contractually — this assertion is a static-only pin for the case
      // where the typedef is used as a named parameter type. The function
      // body that satisfies it is a regular Dart lambda.
      final host = PaneHost<String>(
        provider: provider,
        tabContentBuilder: (ctx, tab) => Text(tab.displayName),
        tabs: tabsManager,
        panes: panesManager,
        emptyCanvasContent: const SizedBox(),
      );
      expect(host.tabContentBuilder, isNotNull);
    });
  });
}
