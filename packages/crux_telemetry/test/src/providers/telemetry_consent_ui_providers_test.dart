// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryTelemetryStorage storage;

  setUp(() => storage = InMemoryTelemetryStorage());

  ProviderContainer containerFor({
    required bool beta,
    required bool dev,
    TelemetryPolicy policy = TelemetryPolicy.absent,
  }) {
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(storage),
        telemetryBetaPeriodProvider.overrideWithValue(beta),
        telemetryDevModeProvider.overrideWithValue(dev),
        telemetryPolicyProvider.overrideWithValue(policy),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('telemetryConsentUiVisibleProvider', () {
    // The same beta × dev × policy shape `telemetryGateProvider` uses, minus
    // the consent term — asking about a pipeline that cannot transmit is the
    // thing this provider exists to prevent, and so is asking about a decision
    // the user is not the one making.
    const expectations = <(TelemetryPolicy, bool beta, bool dev), bool>{
      // No policy: unchanged, the pre-policy behaviour.
      (TelemetryPolicy.absent, true, false): false,
      (TelemetryPolicy.absent, true, true): true,
      (TelemetryPolicy.absent, false, false): true,
      (TelemetryPolicy.absent, false, true): true,
      // A policy — either value — retires BOTH surfaces in every state:
      // individual engineers do not see a telemetry prompt. That has to cover
      // the Settings toggle too, because a toggle the gate ignores tells the
      // user they have a choice and then discards it.
      (TelemetryPolicy.allow, true, false): false,
      (TelemetryPolicy.allow, true, true): false,
      (TelemetryPolicy.allow, false, false): false,
      (TelemetryPolicy.allow, false, true): false,
      (TelemetryPolicy.deny, true, false): false,
      (TelemetryPolicy.deny, true, true): false,
      (TelemetryPolicy.deny, false, false): false,
      (TelemetryPolicy.deny, false, true): false,
    };

    for (final entry in expectations.entries) {
      final (policy, beta, dev) = entry.key;
      test('policy=${policy.name} beta=$beta dev=$dev → ${entry.value}', () {
        expect(
          containerFor(
            beta: beta,
            dev: dev,
            policy: policy,
          ).read(telemetryConsentUiVisibleProvider),
          entry.value,
        );
      });
    }
  });

  group('telemetryConsentPromptVisibleProvider', () {
    test('stays false until the persisted consent has settled', () async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'enabled',
      });
      final container = containerFor(beta: false, dev: false);

      // Synchronously the store still reports `unset`, which is exactly the
      // frame in which a naive gate would re-ask a user who already answered.
      expect(
        container.read(telemetryConsentStoreProvider),
        TelemetryConsentState.unset,
      );
      expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);

      await container.read(telemetryConsentReadyProvider.future);
      expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);
    });

    test('true once a fresh installation has settled on unset', () async {
      final container = containerFor(beta: false, dev: false);

      await container.read(telemetryConsentReadyProvider.future);
      expect(container.read(telemetryConsentPromptVisibleProvider), isTrue);
    });

    test('answering retires it without any "already shown" flag', () async {
      final container = containerFor(beta: false, dev: false);
      await container.read(telemetryConsentReadyProvider.future);
      expect(container.read(telemetryConsentPromptVisibleProvider), isTrue);

      await container
          .read(telemetryConsentStoreProvider.notifier)
          .set(TelemetryConsentState.disabled);

      expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);
    });

    test(
      'never true during the beta, however unset the installation',
      () async {
        final container = containerFor(beta: true, dev: false);

        await container.read(telemetryConsentReadyProvider.future);
        expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);
      },
    );

    for (final policy in [TelemetryPolicy.allow, TelemetryPolicy.deny]) {
      test('never true under an Enterprise `${policy.name}` policy', () async {
        // A `.crux-policy.json` carrying `telemetry: allow | deny` decides
        // org-wide and the individual engineer is never prompted. This
        // is the fresh-installation case — settled, post-beta, `unset` — which
        // is precisely the state that WOULD prompt without the policy, so it is
        // the one that proves the suppression rather than coinciding with it.
        final container = containerFor(beta: false, dev: false, policy: policy);

        await container.read(telemetryConsentReadyProvider.future);
        expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);

        // And nothing was persisted on the policy's behalf: remove the policy
        // and this installation is back to being un-answered, so it prompts.
        expect(storage.values, isNot(contains('telemetry.consent')));
      });
    }

    test('an overlay can still force it false directly', () {
      // Both this and telemetryConsentUiVisibleProvider stay plain Providers,
      // so an overlay with a suppression reason this package does not model
      // needs one override rather than a fork.
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
          telemetryStorageProvider.overrideWithValue(storage),
          telemetryBetaPeriodProvider.overrideWithValue(false),
          telemetryConsentPromptVisibleProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);
    });
  });

  group('openTelemetryDocumentation', () {
    test('the launcher seam has no working default', () {
      // Silently doing nothing when the user taps "Learn more" on a privacy
      // disclosure is the worse failure.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(telemetryUrlLauncherProvider)(
          Uri.parse('https://edacrux.app/telemetry'),
        ),
        throwsUnimplementedError,
      );
    });

    test('the configured page is the one suite disclosure page', () {
      expect(
        testTelemetryConfig.documentationUri.toString(),
        'https://edacrux.app/telemetry',
      );
      expect(kTelemetryDocumentationUri, 'https://edacrux.app/telemetry');
    });
  });
}
