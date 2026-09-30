// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A credential store that cannot be read is not evidence of an unlicensed
/// user.
///
/// The real binding is the OS credential store, and it fails for reasons that
/// have nothing to do with licensing: a locked keychain, a headless CI box, a
/// sandbox with no keyring daemon, a user who cancelled the unlock prompt.
/// Startup must survive all of them without an exception and without quietly
/// telling a paying customer they are on Open Core.
void main() {
  CruxLicenseController controllerOver(LicenseStore store) =>
      CruxLicenseController(
        product: CruxProduct.waveCrux,
        validator: const NoopLicenseValidator(),
        store: store,
        client: KeygenLicenseClient(client: _NeverClient()),
        machine: const LicenseMachineIdentity(
          name: 'lab-01',
          platform: 'macos',
        ),
        openUrl: (_) async {},
        purchaseUrl: Uri.parse('https://example.test/buy'),
        manageUrl: Uri.parse('https://example.test/manage'),
      );

  test('start does not throw when the store is unavailable', () async {
    final controller = controllerOver(_BrokenStore());
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.status.activation, CruxLicenseActivation.openCore);
    expect(
      controller.status.tier,
      LicenseTier.openCore,
      reason: 'the only honest answer when the store cannot be read',
    );
  });

  test('a refresh over a broken store reports rather than throws', () async {
    final controller = controllerOver(_BrokenStore());
    addTearDown(controller.dispose);
    await controller.start();

    // `refresh` reads the credential first; the store throws, and the caller
    // gets an outcome rather than an exception escaping into the UI.
    await expectLater(controller.refresh(), completes);
  });
}

class _BrokenStore implements LicenseStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readCredential() async =>
      throw const _Unavailable('keychain locked');

  @override
  Future<DateTime?> readLastCheck() async => null;

  @override
  Future<String?> readMachineId() async => null;

  @override
  Future<String> readOrCreateFingerprint() async =>
      throw const _Unavailable('keychain locked');

  @override
  Future<void> writeCredential(String credential) async =>
      throw const _Unavailable('keychain locked');

  @override
  Future<void> writeLastCheck(DateTime at) async {}

  @override
  Future<String?> readIssuerSnapshot() async => null;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async {}

  @override
  Future<void> writeMachineId(String? machineId) async {}
}

class _Unavailable implements Exception {
  const _Unavailable(this.message);
  final String message;
}

class _NeverClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw const _Unavailable('no network in tests');
}
