// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_sr_');
    final service = WorkspaceService<String>(
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

  testWidgets('each tab is one named button with its selected state and '
      'its path as the description', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    for (final name in const ['cpu.vcd', 'alu.vcd']) {
      await notifier.openTab(displayName: name, payload: name);
    }

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: ViewerTabBar<String>(
                paneId: ws.activePaneId,
                provider: provider,
                tabFilePath: (tab) => '/kit/${tab.payload}',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    final lines = walk.stops.map((s) => s.line).toList();
    expect(
      lines,
      containsAllInOrder(<String>[
        'cpu.vcd button — /kit/cpu.vcd',
        'alu.vcd button selected — /kit/alu.vcd',
      ]),
    );
    expect(lines.where((l) => l.contains('grouping')), isEmpty);
    handle.dispose();
  });
}
