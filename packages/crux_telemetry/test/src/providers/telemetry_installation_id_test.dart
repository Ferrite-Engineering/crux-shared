// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTelemetryStorage storage;

  setUp(() => storage = InMemoryTelemetryStorage());

  /// A fresh container over the *same* storage — i.e. the next launch.
  Future<String> idFromFreshContainer() async {
    final container = ProviderContainer(
      overrides: [telemetryStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    return container.read(telemetryInstallationIdProvider.future);
  }

  group('telemetryInstallationIdProvider', () {
    test('mints a v4-shaped id and persists it under the fixed key', () async {
      final id = await idFromFreshContainer();

      // The Worker rejects the entire batch on a malformed installation_id,
      // so the shape is a hard requirement, not a nicety.
      expect(kTelemetryInstallationIdPattern.hasMatch(id), isTrue);
      // v4 version nibble and RFC-4122 variant bits.
      expect(id[14], '4');
      expect('89ab'.contains(id[19]), isTrue);

      expect(storage.values['telemetry.installationId'], id);
      expect(kTelemetryInstallationIdKey, 'telemetry.installationId');
    });

    test('is stable across reloads — minted once, then read back', () async {
      final first = await idFromFreshContainer();
      final second = await idFromFreshContainer();
      final third = await idFromFreshContainer();

      // Counting distinct installations only works if a reinstall-free
      // relaunch reports the same id.
      expect(second, first);
      expect(third, first);
    });

    test('two fresh installs get different ids', () async {
      final first = await idFromFreshContainer();

      // A second machine, or the same machine after a reinstall: empty store.
      storage = InMemoryTelemetryStorage();
      final second = await idFromFreshContainer();

      // The id is drawn from a CSPRNG, never computed from the host — so it
      // cannot collide, and equally cannot be correlated back to a machine.
      expect(second, isNot(first));
    });

    test('re-mints when the stored value is malformed', () async {
      storage = InMemoryTelemetryStorage(<String, String>{
        'telemetry.installationId': 'martins-macbook-pro.local',
      });

      final id = await idFromFreshContainer();

      expect(id, isNot('martins-macbook-pro.local'));
      expect(kTelemetryInstallationIdPattern.hasMatch(id), isTrue);
    });
  });

  group('mintTelemetryInstallationId', () {
    test('produces distinct, well-formed ids', () {
      final ids = <String>{
        for (var i = 0; i < 64; i++) mintTelemetryInstallationId(),
      };
      expect(ids, hasLength(64));
      for (final id in ids) {
        expect(kTelemetryInstallationIdPattern.hasMatch(id), isTrue);
      }
    });
  });
}
