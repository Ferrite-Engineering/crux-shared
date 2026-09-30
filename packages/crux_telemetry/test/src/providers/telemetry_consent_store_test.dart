// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTelemetryStorage storage;

  setUp(() => storage = InMemoryTelemetryStorage());

  ProviderContainer containerFor() {
    final container = ProviderContainer(
      overrides: [telemetryStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Reads the store, waiting out the async load `build()` kicks off.
  Future<TelemetryConsentState> settledConsent(
    ProviderContainer container,
  ) async {
    container.read(telemetryConsentStoreProvider); // build + async load
    await container.read(telemetryConsentStoreProvider.notifier).loaded;
    return await container.read(telemetryConsentStoreProvider);
  }

  group('TelemetryConsentStore', () {
    test('defaults to unset on a fresh install', () async {
      final container = containerFor();

      // Synchronously, before the load resolves — the gate must read this as
      // "do not collect", never as consent.
      expect(
        container.read(telemetryConsentStoreProvider),
        TelemetryConsentState.unset,
      );
      expect(await settledConsent(container), TelemetryConsentState.unset);
    });

    test('round-trips enabled through the fixed storage key', () async {
      final writer = containerFor();

      await writer
          .read(telemetryConsentStoreProvider.notifier)
          .set(TelemetryConsentState.enabled);
      expect(
        writer.read(telemetryConsentStoreProvider),
        TelemetryConsentState.enabled,
      );

      // The key is fixed by the suite spec — assert the literal, because the
      // four products and any migration tooling agree on this exact string.
      expect(storage.values['telemetry.consent'], 'enabled');
      expect(kTelemetryConsentKey, 'telemetry.consent');
      expect(TelemetryConsentStore.storageKey, kTelemetryConsentKey);

      // A second container is the next launch, reading the same store back.
      expect(
        await settledConsent(containerFor()),
        TelemetryConsentState.enabled,
      );
    });

    test('round-trips disabled, and disabled is not unset', () async {
      await containerFor()
          .read(telemetryConsentStoreProvider.notifier)
          .set(TelemetryConsentState.disabled);

      expect(
        await settledConsent(containerFor()),
        TelemetryConsentState.disabled,
      );
    });

    test('reads a value written by an earlier session', () async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'enabled',
      });

      expect(
        await settledConsent(containerFor()),
        TelemetryConsentState.enabled,
      );
    });

    test(
      'an unrecognised stored value degrades to unset, never to consent',
      () async {
        storage = InMemoryTelemetryStorage(<String, String>{
          'telemetry.consent': 'sure_why_not',
        });

        expect(
          await settledConsent(containerFor()),
          TelemetryConsentState.unset,
        );
      },
    );

    test('a storage layer that throws degrades to unset', () async {
      // Telemetry may not break a feature flow, so an unreadable store is a
      // store we do not have — and the state it leaves collects nothing.
      final container = ProviderContainer(
        overrides: [
          telemetryStorageProvider.overrideWithValue(
            const _ThrowingTelemetryStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await settledConsent(container), TelemetryConsentState.unset);
    });
  });

  group('TelemetryConsentStore.loaded', () {
    test('completes after the persisted value has been applied', () async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.consent': 'disabled',
      });
      final container = containerFor();

      await container.read(telemetryConsentStoreProvider.notifier).loaded;

      // The whole point of the signal: once it fires, the state is the
      // *stored* one, so the disclosure can trust `unset` to mean "never
      // answered" rather than "not read yet".
      expect(
        container.read(telemetryConsentStoreProvider),
        TelemetryConsentState.disabled,
      );
    });

    test('completes on a fresh install too, with nothing stored', () async {
      final container = containerFor();

      await container.read(telemetryConsentStoreProvider.notifier).loaded;
      expect(
        container.read(telemetryConsentStoreProvider),
        TelemetryConsentState.unset,
      );
    });

    test('completes even when the storage layer throws', () async {
      final container = ProviderContainer(
        overrides: [
          telemetryStorageProvider.overrideWithValue(
            const _ThrowingTelemetryStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // A disclosure that waits forever on an unreadable store is a first
      // launch with no disclosure at all.
      await container
          .read(telemetryConsentStoreProvider.notifier)
          .loaded
          .timeout(const Duration(seconds: 5));
    });

    test('is idempotent — awaiting twice resolves twice', () async {
      final notifier = containerFor().read(
        telemetryConsentStoreProvider.notifier,
      );
      await notifier.loaded;
      await notifier.loaded;
    });
  });

  group('TelemetryConsentState.tryParse', () {
    test('parses every enum name and nothing else', () {
      for (final value in TelemetryConsentState.values) {
        expect(TelemetryConsentState.tryParse(value.name), value);
      }
      expect(TelemetryConsentState.tryParse(null), isNull);
      expect(TelemetryConsentState.tryParse(''), isNull);
      expect(TelemetryConsentState.tryParse('Enabled'), isNull);
    });
  });
}

/// A storage layer that fails every operation — a locked keychain, a read-only
/// profile directory, a plugin that never registered.
class _ThrowingTelemetryStorage extends TelemetryStorage {
  const _ThrowingTelemetryStorage();

  @override
  Future<String?> read(String key) async => throw StateError('no storage');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no storage');

  @override
  Future<void> remove(String key) async => throw StateError('no storage');
}
