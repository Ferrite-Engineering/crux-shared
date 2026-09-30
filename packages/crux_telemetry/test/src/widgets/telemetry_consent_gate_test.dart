// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// ── Harness ──────────────────────────────────────────────────────────────────

/// Every URL the surface asked to open.
late List<Uri> launched;

/// The persistence the gate writes through — the package's stand-in for a
/// product's preferences layer.
late InMemoryTelemetryStorage storage;

Widget _wrap({
  bool beta = false,
  bool dev = false,
  bool isPhoneLayout = false,
  TelemetryPolicy policy = TelemetryPolicy.absent,
  List<Locale>? platformLocales,
  Widget child = const SizedBox.shrink(),
}) {
  launched = <Uri>[];
  return ProviderScope(
    overrides: [
      cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
      telemetryStorageProvider.overrideWithValue(storage),
      telemetryBetaPeriodProvider.overrideWithValue(beta),
      telemetryDevModeProvider.overrideWithValue(dev),
      telemetryPolicyProvider.overrideWithValue(policy),
      if (platformLocales != null)
        telemetryPlatformLocalesProvider.overrideWithValue(platformLocales),
      telemetryUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      home: TelemetryConsentGate(isPhoneLayout: isPhoneLayout, child: child),
    ),
  );
}

Finder get _disclosure => find.byType(TelemetryConsentDisclosure);
Finder get _switch => find.byKey(const Key('telemetryConsentSwitch'));
Finder get _continue => find.byKey(const Key('telemetryConsentContinueButton'));

TelemetryConsentState _storedConsent() =>
    TelemetryConsentState.tryParse(
      storage.values[TelemetryConsentStore.storageKey],
    ) ??
    TelemetryConsentState.unset;

void main() {
  setUp(() => storage = InMemoryTelemetryStorage());

  // ── The region default ─────────────────────────────────────────────────────

  group('the first-launch default', () {
    testWidgets('arrives on outside the opt-in regions', (tester) async {
      await tester.pumpWidget(
        _wrap(platformLocales: const [Locale('en', 'US')]),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
    });

    testWidgets('arrives off in the EEA, the UK, Switzerland and South Korea', (
      tester,
    ) async {
      // The consent-first rule, end to end: platform locale in, toggle
      // position out. The gate is the only place the two are joined, so a
      // regression anywhere along that path lands here.
      for (final locale in const [
        Locale('de', 'DE'),
        Locale('fr', 'FR'),
        Locale('en', 'GB'),
        Locale('de', 'CH'),
        Locale('is', 'IS'),
        Locale('ko', 'KR'),
      ]) {
        await tester.pumpWidget(_wrap(platformLocales: [locale]));
        await tester.pumpAndSettle();

        expect(
          tester.widget<SwitchListTile>(_switch).value,
          isFalse,
          reason: '$locale must arrive opt-in',
        );
      }
    });

    testWidgets('an untouched opt-in prompt stores a refusal', (tester) async {
      // The whole point of the ruling: silence is not consent in those
      // regions. Asserted against the *store*, because what the pipeline
      // later reads is the persisted decision, not the widget's field.
      await tester.pumpWidget(
        _wrap(platformLocales: const [Locale('de', 'DE')]),
      );
      await tester.pumpAndSettle();

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(_storedConsent(), TelemetryConsentState.disabled);
    });
  });

  // ── When it mounts ─────────────────────────────────────────────────────────

  group('TelemetryConsentGate mounting', () {
    testWidgets('mounts once on a fresh post-beta installation', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_disclosure, findsOneWidget);
    });

    testWidgets('does not mount for an installation that already answered', (
      tester,
    ) async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'disabled',
      });
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_disclosure, findsNothing);
    });

    testWidgets('never flashes before the persisted consent has settled', (
      tester,
    ) async {
      // The store publishes `unset` synchronously and loads afterwards. A gate
      // keyed on the state alone would mount here — and re-ask a user who
      // answered on a previous launch.
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'enabled',
      });
      await tester.pumpWidget(_wrap());

      await tester.pump();
      expect(_disclosure, findsNothing);
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);
    });

    testWidgets('leaves the wrapped content alone when it does not mount', (
      tester,
    ) async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'enabled',
      });
      await tester.pumpWidget(
        _wrap(child: const Text('routed', textDirection: TextDirection.ltr)),
      );
      await tester.pumpAndSettle();

      expect(find.text('routed'), findsOneWidget);
      expect(_disclosure, findsNothing);
    });

    testWidgets('shows exactly once per installation', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsOneWidget);

      await tester.tap(_continue);
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);

      // A second launch reads the same store back.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);
    });

    testWidgets('returns on the next launch when left unanswered', (
      tester,
    ) async {
      // Quitting without tapping Continue is not an answer. Nothing is
      // written, so the next launch reads `unset` back and asks again — it
      // must not be treated as "already shown".
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsOneWidget);

      // The app goes away with the disclosure still up.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(_storedConsent(), TelemetryConsentState.unset);
      expect(storage.values, isNot(contains(TelemetryConsentStore.storageKey)));

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsOneWidget);
    });

    testWidgets('never mounts during the beta, whatever the consent', (
      tester,
    ) async {
      // The dark launch extended to the surface: a beta build must not show
      // the disclosure, because there is nothing to consent to.
      await tester.pumpWidget(_wrap(beta: true));
      await tester.pumpAndSettle();

      expect(_disclosure, findsNothing);
      expect(_storedConsent(), TelemetryConsentState.unset);
    });

    testWidgets('mounts during the beta under the dev flag', (tester) async {
      await tester.pumpWidget(_wrap(beta: true, dev: true));
      await tester.pumpAndSettle();

      expect(_disclosure, findsOneWidget);
    });

    for (final policy in [TelemetryPolicy.allow, TelemetryPolicy.deny]) {
      testWidgets('never mounts under an Enterprise `${policy.name}` policy', (
        tester,
      ) async {
        // The IT admin decides in `.crux-policy.json` and individual
        // engineers do not see a telemetry prompt. This is the state that
        // would otherwise mount — fresh, settled, post-beta, `unset`.
        await tester.pumpWidget(
          _wrap(
            policy: policy,
            child: const Text('routed', textDirection: TextDirection.ltr),
          ),
        );
        await tester.pumpAndSettle();

        expect(_disclosure, findsNothing);
        expect(find.text('routed'), findsOneWidget);
        // And the policy recorded nothing on the user's behalf, so removing it
        // leaves an un-answered installation that prompts.
        expect(_storedConsent(), TelemetryConsentState.unset);
      });
    }
  });

  // ── What Continue writes ───────────────────────────────────────────────────

  group('the decision', () {
    testWidgets('the toggle arrives pre-armed on', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
    });

    testWidgets('pre-armed on + Continue writes enabled', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(_storedConsent(), TelemetryConsentState.enabled);
    });

    testWidgets('toggled off + Continue writes disabled', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_switch);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(_switch).value, isFalse);

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(_storedConsent(), TelemetryConsentState.disabled);
    });

    testWidgets('the decision reaches the transmission gate immediately', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(_disclosure),
      );
      expect(container.read(telemetryEnabledProvider), isFalse);

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(container.read(telemetryEnabledProvider), isTrue);
    });

    testWidgets('the documentation link opens the suite telemetry page', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('telemetryConsentLearnMoreButton')),
      );
      await tester.pumpAndSettle();

      expect(launched, [Uri.parse('https://edacrux.app/telemetry')]);
      // Reading the docs is not an answer — the disclosure stays up.
      expect(_disclosure, findsOneWidget);
    });

    testWidgets('the system back gesture cannot dismiss it unanswered', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(isPhoneLayout: true));
      await tester.pumpAndSettle();

      final popScope = tester.widget<PopScope<dynamic>>(
        find.descendant(
          of: _disclosure,
          matching: find.byType(PopScope<dynamic>),
        ),
      );
      expect(popScope.canPop, isFalse);
      expect(_storedConsent(), TelemetryConsentState.unset);
    });
  });

  // ── Layout ─────────────────────────────────────────────────────────────────

  group('presentation follows the host classification', () {
    testWidgets('phone layout renders the full-screen sheet', (tester) async {
      await tester.pumpWidget(_wrap(isPhoneLayout: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentSheet')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentDialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('otherwise renders the dialog card', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentSheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
