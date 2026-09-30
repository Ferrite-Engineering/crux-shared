// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _config = CruxUpdateConfig(
  productName: 'NetCrux',
  manifestUri: 'https://updates.example.test/manifest.json',
  downloadPageUri: 'https://example.test/download',
  appStoreUri: 'https://apps.apple.test/netcrux',
  playStoreUri: 'https://play.google.test/netcrux',
);

/// Stub notifier that returns a fixed status without launch checks or timers,
/// and records every gated re-check the banner asks for.
class _StubUpdateStatusNotifier extends UpdateStatusNotifier {
  _StubUpdateStatusNotifier(this._state);

  final UpdateStatus _state;
  int scheduledChecks = 0;

  @override
  UpdateStatus build() => _state;

  @override
  Future<void> runScheduledCheck() async {
    scheduledChecks++;
  }
}

UpdateInfo _info({
  String version = '1.2.0',
  bool mandatory = false,
  String? changelogUrl = 'https://example.test/releases/1.2.0',
}) => UpdateInfo(
  version: version,
  mandatory: mandatory,
  changelogUrl: changelogUrl,
);

void main() {
  late List<Uri> launched;
  late _StubUpdateStatusNotifier notifier;

  setUp(() => launched = <Uri>[]);

  Widget wrap(
    UpdateStatus status, {
    TargetPlatform platform = TargetPlatform.macOS,
    bool isWeb = false,
  }) {
    notifier = _StubUpdateStatusNotifier(status);
    return ProviderScope(
      overrides: [
        cruxUpdateConfigProvider.overrideWithValue(_config),
        updateStatusProvider.overrideWith(() => notifier),
        updateUrlLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: UpdateBanner(
            isWeb: isWeb,
            child: const Text('routed-content'),
          ),
        ),
      ),
    );
  }

  testWidgets('current renders the child with no banner', (tester) async {
    await tester.pumpWidget(wrap(const UpdateStatusCurrent()));
    await tester.pumpAndSettle();
    expect(find.text('routed-content'), findsOneWidget);
    expect(find.byType(UpdateAvailableBanner), findsNothing);
  });

  testWidgets('checking and error render no banner', (tester) async {
    await tester.pumpWidget(wrap(const UpdateStatusChecking()));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableBanner), findsNothing);

    await tester.pumpWidget(wrap(const UpdateStatusError()));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableBanner), findsNothing);
  });

  testWidgets('available shows the banner above the child', (tester) async {
    await tester.pumpWidget(wrap(UpdateStatusAvailable(_info())));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableBanner), findsOneWidget);
    expect(find.text('routed-content'), findsOneWidget);
    expect(find.textContaining('NetCrux 1.2.0'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(UpdateAvailableBanner)).dy,
      lessThan(tester.getTopLeft(find.text('routed-content')).dy),
    );
  });

  testWidgets('web never shows the banner, even with an update available', (
    tester,
  ) async {
    // A web app self-updates on deploy — a "download the new version" banner
    // is meaningless there. The check itself still runs on web for the
    // server_time hardening; only the banner is gated.
    await tester.pumpWidget(wrap(UpdateStatusAvailable(_info()), isWeb: true));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailableBanner), findsNothing);
    expect(find.text('routed-content'), findsOneWidget);
  });

  testWidgets('dismiss hides the banner for the session', (tester) async {
    await tester.pumpWidget(wrap(UpdateStatusAvailable(_info())));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableBanner), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableBanner), findsNothing);
    expect(find.text('routed-content'), findsOneWidget);
  });

  testWidgets('mandatory is non-dismissible (no close affordance)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(UpdateStatusAvailable(_info(mandatory: true))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableBanner), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('View Changes opens the changelog URL', (tester) async {
    await tester.pumpWidget(wrap(UpdateStatusAvailable(_info())));
    await tester.pumpAndSettle();

    await tester.tap(find.text(const CruxUpdateStringsEn().viewChangesAction));
    expect(launched, [Uri.parse('https://example.test/releases/1.2.0')]);
  });

  testWidgets('Update Now opens the download page on desktop', (tester) async {
    await tester.pumpWidget(wrap(UpdateStatusAvailable(_info())));
    await tester.pumpAndSettle();

    await tester.tap(find.text(const CruxUpdateStringsEn().updateNowAction));
    expect(launched, [_config.downloadPageUri]);
  });

  testWidgets('Update Now opens the App Store on iOS', (tester) async {
    await tester.pumpWidget(
      wrap(UpdateStatusAvailable(_info()), platform: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(const CruxUpdateStringsEn().updateNowAction));
    expect(launched, [_config.appStoreUri]);
  });

  testWidgets('no View Changes button when the changelog URL is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(UpdateStatusAvailable(_info(changelogUrl: null))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(const CruxUpdateStringsEn().viewChangesAction),
      findsNothing,
    );
    expect(
      find.text(const CruxUpdateStringsEn().updateNowAction),
      findsOneWidget,
    );
  });

  testWidgets('no View Changes button when the changelog URL is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(UpdateStatusAvailable(_info(changelogUrl: ''))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(const CruxUpdateStringsEn().viewChangesAction),
      findsNothing,
    );
  });

  testWidgets('app resume triggers the gated re-check', (tester) async {
    await tester.pumpWidget(wrap(const UpdateStatusCurrent()));
    await tester.pumpAndSettle();
    expect(notifier.scheduledChecks, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(notifier.scheduledChecks, 1);
  });

  testWidgets('a non-resume lifecycle change does not re-check', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const UpdateStatusCurrent()));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(notifier.scheduledChecks, 0);
  });

  testWidgets('host metrics reach the strip', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cruxUpdateConfigProvider.overrideWithValue(_config),
          updateStatusProvider.overrideWith(
            () => _StubUpdateStatusNotifier(UpdateStatusAvailable(_info())),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: UpdateBanner(
              isWeb: false,
              metrics: CruxUpdateBannerMetrics(touchTarget: 56),
              child: Text('routed-content'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(IconButton)).height, greaterThan(50));
  });
}
