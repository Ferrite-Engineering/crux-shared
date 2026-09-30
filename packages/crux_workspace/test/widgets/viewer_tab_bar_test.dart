// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// This file pins the public surface so products consuming the package don't
// accidentally regress the constructor shape.
//
// Behavioural coverage lives alongside it, not here:
//   * viewer_tab_bar_context_menu_test.dart — context-menu execution.
//   * viewer_tab_bar_scroll_flags_test.dart — chevron/scroll-listener
//     lifecycle.
//   * viewer_tab_bar_seams_test.dart / _parity_seams_test.dart — the
//     additive builder seams.
//
// (The "Riverpod-3.x timing quirk" this comment used to cite was a harness
// mistake, not a framework one: the tab/pane container managers have to be
// parented to the container that hosts the workspace provider, or the bar
// resolves a second, empty workspace whose pane ids don't match.)

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
  group('ViewerTabBar public surface', () {
    late Directory tempDir;
    late WorkspaceService<String> service;
    late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
    provider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('crux_vtb_surface_');
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

    test('constructor accepts the documented parameters', () {
      final paneId = PaneId.generate();
      final bar = ViewerTabBar<String>(
        paneId: paneId,
        provider: provider,
        defaultPayloadBuilder: () => 'p',
        isActivePane: true,
      );
      expect(bar.paneId, equals(paneId));
      expect(bar.isActivePane, isTrue);
      expect(bar.defaultPayloadBuilder, isNotNull);
      expect(bar.strings, isA<ViewerTabBarStringsEn>());
    });

    // NOTE: the enum-shape assertion that used to live here (values has
    // length 4, names match labels) was removed deliberately. It passed
    // unchanged even if every handler in `_showMenuAt` were replaced with
    // `return;` — an enum-shape test standing in for a behaviour test, with
    // the whole menu-execution block uncovered behind it. The real
    // menu-execution coverage lives in
    // `viewer_tab_bar_context_menu_test.dart`; add cases there, not here.
  });

  group('ViewerTabBarStringsEn', () {
    const s = ViewerTabBarStringsEn();

    test('exposes every string field non-empty', () {
      final fields = <String>[
        s.closeTabTooltip,
        s.newTabTooltip,
        s.newTabDefaultDisplayName,
        s.unnamedTabFallback,
        s.closeTabMenuItem,
        s.closeOtherTabsMenuItem,
        s.closeTabsToTheRightMenuItem,
        s.moveToNewWindowMenuItem,
        s.multiWindowUnavailableTooltip,
        s.activePaneAccessibilityLabel,
        s.dragToPaneAccessibilityHint,
        s.reorderHandleTooltip,
      ];
      for (final f in fields) {
        expect(f, isNotEmpty);
      }
    });
  });
}
