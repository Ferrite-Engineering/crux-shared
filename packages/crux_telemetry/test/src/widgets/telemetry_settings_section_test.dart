// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

Widget _wrap({Widget? body}) {
  launched = <Uri>[];
  return ProviderScope(
    overrides: [
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
