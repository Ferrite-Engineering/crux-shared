// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../harness.dart';

// ── Harness ──────────────────────────────────────────────────────────────────

/// Minimum hit area for a tappable element on touch.
const double _minTarget = 44;

late List<Uri> launched;
late InMemoryTelemetryStorage storage;

void _setSurface(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

Widget _wrap({Widget? body, List<Override> extraOverrides = const []}) {
  launched = <Uri>[];
  return ProviderScope(
    overrides: [
      ...extraOverrides,
      cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
      telemetryStorageProvider.overrideWithValue(storage),
      // Post-beta: the section exists at all only on a build that can
      // transmit, and the round-trip is only meaningful there.
      telemetryBetaPeriodProvider.overrideWithValue(false),
      telemetryDevModeProvider.overrideWithValue(false),
      telemetryUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      home: Scaffold(
        body:
            body ??
            const SingleChildScrollView(child: TelemetrySettingsSection()),
      ),
    ),
  );
}

Finder get _switch => find.byKey(const Key('settingsTelemetrySwitch'));

TelemetryConsentState _storedConsent() =>
    TelemetryConsentState.tryParse(
      storage.values[TelemetryConsentStore.storageKey],
    ) ??
    TelemetryConsentState.unset;

void main() {
  setUp(() => storage = InMemoryTelemetryStorage());

  group('TelemetrySettingsSection', () {
    testWidgets('an unanswered installation reads as off', (tester) async {
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // `unset` is not consent, and the switch must not imply it is.
      expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
    });

    testWidgets('reflects a value stored by an earlier session', (
      tester,
    ) async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'enabled',
      });
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
    });

    testWidgets('switching on writes enabled, switching off writes disabled', (
      tester,
    ) async {
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_switch);
      await tester.pumpAndSettle();
      expect(_storedConsent(), TelemetryConsentState.enabled);

      await tester.tap(_switch);
      await tester.pumpAndSettle();
      // Not back to `unset` — an answer, once given, stays an answer.
      expect(_storedConsent(), TelemetryConsentState.disabled);
    });

    testWidgets('the documentation button opens the suite telemetry page', (
      tester,
    ) async {
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settingsTelemetryDocsButton')));
      await tester.pumpAndSettle();

      expect(launched, [Uri.parse('https://edacrux.app/telemetry')]);
    });

    testWidgets('the switch clears the 44 dp touch floor', (tester) async {
      _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final size = tester.getSize(_switch);
      expect(size.height, greaterThanOrEqualTo(_minTarget));
      expect(size.width, greaterThanOrEqualTo(_minTarget));
    });
  });

  // ── The installation id row ────────────────────────────────────────────────

  group('the installation id row', () {
    const storedId = '00000000-0000-4000-8000-0000000000aa';
    final idText = find.byKey(const Key('settingsTelemetryInstallationId'));
    final noneText = find.byKey(
      const Key('settingsTelemetryInstallationIdNone'),
    );
    final copyButton = find.byKey(
      const Key('settingsTelemetryInstallationIdCopy'),
    );

    bool copyEnabled(WidgetTester tester) =>
        tester.widget<ButtonStyleButton>(copyButton).onPressed != null;

    for (final consent in <String?>[null, 'disabled']) {
      testWidgets(
        'opening Settings with measurement off (${consent ?? 'unset'}) '
        'creates no id',
        (tester) async {
          storage = InMemoryTelemetryStorage(<String, String>{
            'telemetry.consent': ?consent,
          });
          _setSurface(tester, const Size(900, 700));
          await tester.pumpWidget(_wrap());
          await tester.pumpAndSettle();

          // The privacy policy says the id does not exist until the user
          // opts in. Opening this screen is not opting in.
          expect(
            storage.values.containsKey(kTelemetryInstallationIdKey),
            isFalse,
          );
          expect(idText, findsNothing);
          expect(noneText, findsOneWidget);
          expect(
            find.text(
              const CruxTelemetryStringsEn().settingsInstallationIdNone,
            ),
            findsOneWidget,
          );
          expect(copyEnabled(tester), isFalse);
        },
      );
    }

    testWidgets('a malformed stored value shows as no id and is left alone', (
      tester,
    ) async {
      storage = InMemoryTelemetryStorage(<String, String>{
        kTelemetryInstallationIdKey: 'not-an-id',
      });
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(noneText, findsOneWidget);
      expect(storage.values[kTelemetryInstallationIdKey], 'not-an-id');
    });

    testWidgets('an id left by an earlier opt-in still shows while off', (
      tester,
    ) async {
      // Opted in, then out: the id is what a deletion request needs.
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'disabled',
        kTelemetryInstallationIdKey: storedId,
      });
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
      expect(tester.widget<SelectableText>(idText).data, storedId);
      expect(noneText, findsNothing);
      expect(copyEnabled(tester), isTrue);
    });

    testWidgets('Copy puts the id on the clipboard and says so', (
      tester,
    ) async {
      storage = InMemoryTelemetryStorage(<String, String>{
        kTelemetryInstallationIdKey: storedId,
      });
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(copied, [
        <String, Object?>{'text': storedId},
      ]);
      expect(
        find.text(const CruxTelemetryStringsEn().settingsInstallationIdCopied),
        findsOneWidget,
      );
    });

    testWidgets('turning measurement on creates the id and shows it', (
      tester,
    ) async {
      _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(
        _wrap(
          extraOverrides: [
            telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
            telemetryHttpClientProvider.overrideWithValue(
              MockClient(
                (_) async => http.Response('{"accepted":1,"dropped":0}', 202),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The product records at launch, as every product does: with the
      // question unanswered that event waits rather than sending.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TelemetrySettingsSection)),
      );
      container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('workspace.restored'));
      await tester.pumpAndSettle();
      expect(storage.values.containsKey(kTelemetryInstallationIdKey), isFalse);
      expect(noneText, findsOneWidget);

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      // The gate is open, so the live service exists. Its flush resolves the
      // envelope through this resolver, the one place the id is created; run
      // it directly rather than through the service's timers and disk queue.
      expect(
        container.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
      final envelope = container.read(telemetryEnvelopeResolverProvider)();
      await tester.pumpAndSettle();
      expect((await envelope)?.installationId, isNotNull);
      await tester.pumpAndSettle();

      final minted = storage.values[kTelemetryInstallationIdKey];
      expect(minted, isNotNull);
      expect(kTelemetryInstallationIdPattern.hasMatch(minted!), isTrue);
      expect(tester.widget<SelectableText>(idText).data, minted);
      expect(noneText, findsNothing);
      expect(copyEnabled(tester), isTrue);

      // Unmount so the live service's flush timer is cancelled.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ── One setting, two entry points ──────────────────────────────────────────

  group('the Settings toggle and the disclosure are the same switch', () {
    /// Both surfaces in one tree: the gate mounts the disclosure while consent
    /// is unset, and the section renders beneath it.
    Widget both() => _wrap(
      body: const TelemetryConsentGate(
        child: SingleChildScrollView(child: TelemetrySettingsSection()),
      ),
    );

    testWidgets('what the disclosure wrote is what Settings shows', (
      tester,
    ) async {
      _setSurface(tester, const Size(1440, 900));
      await tester.pumpWidget(both());
      await tester.pumpAndSettle();

      // Decline in the disclosure.
      await tester.tap(find.byKey(const Key('telemetryConsentSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('telemetryConsentContinueButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TelemetryConsentDisclosure), findsNothing);
      expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
      expect(_storedConsent(), TelemetryConsentState.disabled);
    });

    testWidgets('and answering in Settings retires the disclosure', (
      tester,
    ) async {
      _setSurface(tester, const Size(1440, 900));
      await tester.pumpWidget(both());
      await tester.pumpAndSettle();
      expect(find.byType(TelemetryConsentDisclosure), findsOneWidget);

      // The section is behind the disclosure's modal barrier, so drive the
      // store the way the tile's callback does rather than through a tap the
      // real UI would not permit either.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TelemetrySettingsSection)),
      );
      await container
          .read(telemetryConsentStoreProvider.notifier)
          .set(TelemetryConsentState.enabled);
      await tester.pumpAndSettle();

      expect(find.byType(TelemetryConsentDisclosure), findsNothing);
      expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
    });

    testWidgets('both surfaces read the same gate provider', (tester) async {
      _setSurface(tester, const Size(1440, 900));
      await tester.pumpWidget(both());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TelemetrySettingsSection)),
      );
      expect(container.read(telemetryConsentUiVisibleProvider), isTrue);
    });
  });
}
