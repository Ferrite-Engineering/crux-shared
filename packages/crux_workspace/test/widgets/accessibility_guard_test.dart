// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accessibility guidelines for `ViewerTabBar`.
///
/// A suite-wide audit found ZERO accessibility tests
/// across nine repos while `flutter_test` ships four guideline matchers for
/// free.
///
/// The tab bar is the highest-traffic shared surface in the suite — it is the
/// primary navigation chrome in all four products, present in every session.
/// It is also where the audit found its one genuine unlabelled control in
/// crux-shared: the scroll chevrons, which were bare `IconButton`s announced
/// as "button" until 2026-08-17.
///
/// Assertions run in **both themes**, because contrast is a property of the
/// colour pair rather than the widget: a surface can pass in light and fail in
/// dark, and the suite ships both.
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
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_a11y_');
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

  _welcomeGuards();

  for (final brightness in Brightness.values) {
    testWidgets('ViewerTabBar meets the guidelines (${brightness.name})', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ws = await container.read(provider.future);
      final notifier = container.read(provider.notifier);
      // Several tabs, so the strip renders chips, close affordances and — at
      // this width — the scroll chevrons that were the audit's finding.
      for (final name in const ['cpu.vcd', 'alu.vcd', 'regfile.vcd']) {
        await notifier.openTab(displayName: name, payload: name);
      }

      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF4650C8),
                brightness: brightness,
              ),
            ),
            home: Scaffold(
              body: SizedBox(
                width: 420,
                child: ViewerTabBar<String>(
                  paneId: ws.activePaneId,
                  provider: provider,
                  defaultPayloadBuilder: () => 'new',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });
  }
}

/// Accessibility guidelines for the welcome screen.
///
/// `EmptyCanvasState` is the suite's shared welcome shell — the first surface a
/// user sees in all four products, and the one they return to after closing
/// their last tab. It renders a title, a subtitle, a version line and a row of
/// primary actions, which is a lot of low-emphasis text in one place and
/// therefore a natural home for a contrast regression.
void _welcomeGuards() {
  for (final brightness in Brightness.values) {
    testWidgets('EmptyCanvasState meets the guidelines (${brightness.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4650C8),
              brightness: brightness,
            ),
          ),
          home: Scaffold(
            body: EmptyCanvasState(
              title: 'Welcome to TestCrux',
              subtitle: 'Open a design to begin.',
              versionLabel: 'v0.8.0',
              primaryActions: [
                FilledButton(onPressed: () {}, child: const Text('Open…')),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Open Workspace…'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      handle.dispose();
    });
  }
}
