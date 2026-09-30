// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

class _StringPayloadCodec extends WorkspaceCodec<String> {
  const _StringPayloadCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String payload) => {'value': payload};

  @override
  String payloadFromJson(Map<String, Object?> json) =>
      json['value'] as String? ?? '';

  @override
  String displayNameFor(String payload) => payload;
}

void main() {
  group('Workspace<String>', () {
    const codec = _StringPayloadCodec();

    test('empty() yields zero tabs and a single pane', () {
      final ws = Workspace<String>.empty();
      expect(ws.tabs, isEmpty);
      expect(ws.panes, hasLength(1));
      expect(ws.activePaneId, equals(ws.panes.single.id));
      expect(ws.isEmpty, isTrue);
      expect(ws.activeTabId, isNull);
    });

    test('constructor rejects unknown panes', () {
      final pane = WorkspacePane(id: PaneId.generate());
      expect(
        () => Workspace<String>(
          tabs: [
            WorkspaceTab(
              id: TabId.generate(),
              displayName: 'a',
              paneId: PaneId.generate(),
              payload: 'hello',
            ),
          ],
          panes: [pane],
          activePaneId: pane.id,
        ),
        throwsA(isA<WorkspaceInvariantException>()),
      );
    });

    test('constructor rejects 3+ panes', () {
      expect(
        () => Workspace<String>(
          tabs: const [],
          panes: [
            WorkspacePane(id: PaneId.generate()),
            WorkspacePane(id: PaneId.generate()),
            WorkspacePane(id: PaneId.generate()),
          ],
          activePaneId: PaneId.generate(),
        ),
        throwsA(isA<WorkspaceInvariantException>()),
      );
    });

    test('round-trips through JSON', () {
      final pane = WorkspacePane(id: PaneId.generate());
      final tab = WorkspaceTab(
        id: TabId.generate(),
        displayName: 'first',
        paneId: pane.id,
        payload: 'hello-world',
      );
      final ws = Workspace<String>(
        tabs: [tab],
        panes: [pane.copyWith(activeTabId: tab.id)],
        activePaneId: pane.id,
        extras: const {'stripVisible': true},
      );
      final json = ws.toJson(codec);
      final restored = Workspace<String>.fromJson(json, codec);
      expect(restored, equals(ws));
      expect(restored.tabs.single.payload, equals('hello-world'));
      expect(restored.extras['stripVisible'], isTrue);
    });

    test('rejects unknown schema versions', () {
      expect(
        () => Workspace<String>.fromJson(
          const {
            'version': 99,
            'panes': [
              {'id': '11111111-1111-1111-1111-111111111111'},
            ],
            'activePaneId': '11111111-1111-1111-1111-111111111111',
          },
          codec,
        ),
        throwsA(isA<WorkspaceSchemaVersionException>()),
      );
    });

    test('tabsForPane filters by pane id', () {
      final paneA = WorkspacePane(id: PaneId.generate());
      final paneB = WorkspacePane(id: PaneId.generate());
      final tab1 = WorkspaceTab(
        id: TabId.generate(),
        displayName: '1',
        paneId: paneA.id,
        payload: '1',
      );
      final tab2 = WorkspaceTab(
        id: TabId.generate(),
        displayName: '2',
        paneId: paneB.id,
        payload: '2',
      );
      final ws = Workspace<String>(
        tabs: [tab1, tab2],
        panes: [paneA, paneB],
        activePaneId: paneA.id,
      );
      expect(ws.tabsForPane(paneA.id), [tab1]);
      expect(ws.tabsForPane(paneB.id), [tab2]);
    });
  });

  group('WorkspaceCodec contract', () {
    test('default impl preserves round-trip and display name', () {
      const codec = _StringPayloadCodec();
      final json = codec.payloadToJson('hi');
      expect(codec.payloadFromJson(json), equals('hi'));
      expect(codec.displayNameFor('hi'), equals('hi'));
      expect(codec.schemaVersion, equals(1));
    });
  });
}
