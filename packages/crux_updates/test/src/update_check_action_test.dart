// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _config = CruxUpdateConfig(
  productName: 'NetCrux',
  manifestUri: 'https://updates.example.test/manifest.json',
  downloadPageUri: 'https://example.test/download',
);

const _buildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.2',
);

/// Returns the fixed [_state] with no launch-check / timer side effects, and a
/// counted no-op [checkNow] so the surfaced result is exactly that state.
class _StubUpdateStatusNotifier extends UpdateStatusNotifier {
  _StubUpdateStatusNotifier(this._state);

  final UpdateStatus _state;
  int manualChecks = 0;

  /// When set, [checkNow] blocks on it — letting a test observe the in-flight
  /// state that an instantly-resolving check would skip past.
  Completer<void>? gate;

  @override
  UpdateStatus build() => _state;

  @override
  Future<void> checkNow() async {
    manualChecks++;
    await gate?.future;
  }
}

void main() {
  late _StubUpdateStatusNotifier notifier;

  Widget host(UpdateStatus state, {bool withBuildInfo = true}) {
    notifier = _StubUpdateStatusNotifier(state);
    return ProviderScope(
      overrides: [
        cruxUpdateConfigProvider.overrideWithValue(_config),
        updateStatusProvider.overrideWith(() => notifier),
        if (withBuildInfo)
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Watch so the build-info future resolves before the tap; the
              // "up to date" toast names the running version.
              ref.watch(updateBuildInfoProvider);
              return Center(
                child: ElevatedButton(
                  onPressed: () => runManualUpdateCheck(context, ref),
                  child: const Text('check'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> tapCheck(WidgetTester tester) async {
    await tester.pump(); // resolve the build-info future
    await tester.tap(find.text('check'));
    await tester.pump(); // run the async handler + show the SnackBar
  }

  const strings = CruxUpdateStringsEn(productName: 'NetCrux');

  testWidgets('up-to-date shows a confirmation naming the version', (
    tester,
  ) async {
    await tester.pumpWidget(host(const UpdateStatusCurrent()));
    await tapCheck(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('1.2.3'), findsOneWidget);
  });

  testWidgets('the manual check always runs the notifier', (tester) async {
    await tester.pumpWidget(host(const UpdateStatusCurrent()));
    await tapCheck(tester);

    expect(notifier.manualChecks, 1);
  });

  testWidgets("error shows a non-fatal \"couldn't check\" message", (
    tester,
  ) async {
    await tester.pumpWidget(host(const UpdateStatusError()));
    await tapCheck(tester);

    expect(find.text(strings.checkFailed), findsOneWidget);
  });

  testWidgets('an available update shows no toast (the banner surfaces it)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const UpdateStatusAvailable(UpdateInfo(version: '9.9.9'))),
    );
    await tapCheck(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a still-checking state shows no outcome toast', (tester) async {
    await tester.pumpWidget(host(const UpdateStatusChecking()));
    await tapCheck(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the in-flight toast is shown, then retired', (tester) async {
    await tester.pumpWidget(host(const UpdateStatusCurrent()));
    await tester.pump(); // resolve the build-info future
    // Hold the check open so the in-flight toast is observable; with an
    // instantly-resolving check the outcome replaces it inside one frame.
    final gate = Completer<void>();
    notifier.gate = gate;

    await tester.tap(find.text('check'));
    await tester.pump(); // the checking toast is queued synchronously
    expect(find.text(strings.checkInProgress), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(strings.checkInProgress), findsNothing);
    expect(find.text(strings.checkUpToDate('1.2.3')), findsOneWidget);
  });

  testWidgets('an unknown running version still reports up to date', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const UpdateStatusCurrent(), withBuildInfo: false),
    );
    await tapCheck(tester);
    await tester.pumpAndSettle();

    expect(find.text(strings.checkUpToDate('')), findsOneWidget);
  });
}
