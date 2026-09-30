// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WorkspaceLifecycleObserver` had **zero** coverage: its
/// body could have been deleted without turning a single test red, and its
/// documented "flushes on pause/detach" contract was entirely unverified.
/// These tests drive the real lifecycle callbacks through the binding.
///
/// The debounce is deliberately long (30 s) so "was the pending save actually
/// forced out?" is a real question. Saves are captured in memory rather than
/// written to disk — `testWidgets` runs in fake async, so a real file write
/// would never settle and the assertion would be about the harness rather
/// than the widget.

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

/// Records every `save` instead of touching the filesystem.
class _RecordingService extends WorkspaceService<String> {
  _RecordingService()
    : super(codec: const _StringCodec(), logger: _ignore, fileName: 'x.json');

  static void _ignore(String _) {}

  final List<Workspace<String>> saves = [];

  @override
  Future<Workspace<String>> load() async => Workspace<String>.empty();

  @override
  Future<void> save(Workspace<String> workspace) async => saves.add(workspace);
}

void main() {
  late _RecordingService service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() {
    service = _RecordingService();
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: const Duration(seconds: 30),
          ),
        );
  });

  Future<ProviderContainer> pumpObserver(
    WidgetTester tester, {
    List<Future<void> Function()> additionalFlushes = const [],
    Widget child = const SizedBox(),
  }) async {
    final container = ProviderContainer();
    await container.read(provider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WorkspaceLifecycleObserver<String>(
            provider: provider,
            additionalFlushes: additionalFlushes,
            child: child,
          ),
        ),
      ),
    );
    // Disposed inside the test body, not via addTearDown: the fake-async
    // pending-timer check runs before tearDown, and the debounce timer must
    // be cancelled before then.
    return container;
  }

  /// Drives the real platform lifecycle transition the engine sends.
  Future<void> sendLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }

  testWidgets('renders its child unchanged', (tester) async {
    final container = await pumpObserver(tester, child: const Text('inner'));
    expect(find.text('inner'), findsOneWidget);
    container.dispose();
  });

  testWidgets('paused forces the debounced workspace save out', (tester) async {
    final container = await pumpObserver(tester);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'A', payload: 'a');

    // Still 30 s from being written.
    expect(service.saves, isEmpty);

    await sendLifecycle(tester, AppLifecycleState.paused);
    await tester.pump();

    expect(
      service.saves,
      hasLength(1),
      reason: 'paused must persist the pending workspace state',
    );
    expect(service.saves.single.tabs, hasLength(1));
    container.dispose();
  });

  testWidgets('detached forces the save out too', (tester) async {
    final container = await pumpObserver(tester);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'B', payload: 'b');

    await sendLifecycle(tester, AppLifecycleState.detached);
    await tester.pump();

    expect(service.saves, hasLength(1));
    container.dispose();
  });

  testWidgets('resumed and inactive do NOT flush', (tester) async {
    final container = await pumpObserver(tester);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'C', payload: 'c');

    await sendLifecycle(tester, AppLifecycleState.inactive);
    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();

    expect(
      service.saves,
      isEmpty,
      reason: 'only paused/detached are terminal enough to force a write',
    );
    // Dispose flushes the pending payload, which is the separate contract.
    container.dispose();
  });

  group('additionalFlushes — reaching beyond the observer’s own scope', () {
    testWidgets('per-scope hooks run on pause', (tester) async {
      // The observer mounts ABOVE the tab scopes, so per-tab notifiers are
      // unreachable through `provider`. Without this seam their pending state
      // is silently lost on a mobile pause — the last callback the process
      // reliably gets before being killed.
      var perTabFlushes = 0;
      final container = await pumpObserver(
        tester,
        additionalFlushes: [
          () async => perTabFlushes++,
          () async => perTabFlushes++,
        ],
      );

      await sendLifecycle(tester, AppLifecycleState.paused);
      await tester.pump();

      expect(perTabFlushes, 2);
      container.dispose();
    });

    testWidgets('hooks do not run on resumed', (tester) async {
      var calls = 0;
      final container = await pumpObserver(
        tester,
        additionalFlushes: [() async => calls++],
      );

      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();

      expect(calls, 0);
      container.dispose();
    });

    testWidgets(
      'a failing hook is reported but does not abandon the workspace save '
      'or its siblings',
      (tester) async {
        var siblingRan = false;
        final container = await pumpObserver(
          tester,
          additionalFlushes: [
            () async => throw StateError('per-tab flush blew up'),
            () async {
              siblingRan = true;
            },
          ],
        );
        await container
            .read(provider.notifier)
            .openTab(displayName: 'D', payload: 'd');

        await sendLifecycle(tester, AppLifecycleState.paused);
        await tester.pump();

        // The failure surfaces through FlutterError rather than vanishing —
        // a silently-swallowed flush failure is how data loss stays invisible.
        expect(tester.takeException(), isA<StateError>());
        expect(
          siblingRan,
          isTrue,
          reason: 'one bad hook must not cancel the others',
        );
        expect(
          service.saves,
          hasLength(1),
          reason: 'the workspace write must survive a product-side failure',
        );
        container.dispose();
      },
    );

    testWidgets('a hook that throws synchronously is contained', (
      tester,
    ) async {
      var siblingRan = false;
      final container = await pumpObserver(
        tester,
        additionalFlushes: [
          // Throws before it ever returns a Future.
          () => throw StateError('sync boom'),
          () async {
            siblingRan = true;
          },
        ],
      );

      await sendLifecycle(tester, AppLifecycleState.paused);
      await tester.pump();

      expect(tester.takeException(), isA<StateError>());
      expect(siblingRan, isTrue);
      container.dispose();
    });
  });

  testWidgets('an unmounted observer stops listening', (tester) async {
    var calls = 0;
    final container = await pumpObserver(
      tester,
      additionalFlushes: [() async => calls++],
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await sendLifecycle(tester, AppLifecycleState.paused);
    await tester.pump();

    expect(
      calls,
      0,
      reason: 'dispose must remove the widget from the binding observers',
    );
    container.dispose();
  });
}
