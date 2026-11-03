// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// A tab's context menu opens at the pointer when the bar sits in a nested
/// navigator below a strip, with another strip above the root navigator. The
/// menu's position is measured against the root overlay, so it is laid out in
/// the root overlay too.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_nested_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  testWidgets('right-clicking a tab opens its menu at the pointer', (
    tester,
  ) async {
    final provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: WorkspaceService<String>(
              codec: const _StringCodec(),
              directoryFactory: () async => tempDir,
              logger: (_) {},
            ),
            autoSaveDebounce: Duration.zero,
          ),
        );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(
          displayName: 'A',
          payload: 'A',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => Column(
            children: <Widget>[
              const SizedBox(height: 90),
              Expanded(child: child!),
            ],
          ),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: 85),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (context) => Material(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ViewerTabBar<String>(
                            paneId: ws.activePaneId,
                            provider: provider,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final click = tester.getCenter(find.text('A'));
    final gesture = await tester.startGesture(
      click,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    const strings = ViewerTabBarStringsEn();
    final menu = tester.getRect(
      find
          .ancestor(
            of: find.text(strings.closeTabMenuItem),
            matching: find.byType(Material),
          )
          .first,
    );
    expect((menu.left - click.dx).abs(), lessThan(4));
    expect((menu.top - click.dy).abs(), lessThan(4));
  });
}
