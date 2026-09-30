// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_secrets/crux_secrets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the macOS keychain configuration of the default secret store.
///
/// This is a regression guard, not a unit test of behaviour. The plugin's own
/// default for `usesDataProtectionKeychain` is `true`, and `true` is the
/// configuration that FAILS on every build in this suite that is not signed
/// with a provisioned Apple development certificate — CI integration builds,
/// contributors' local `flutter run`, and ad-hoc "Sign to Run Locally"
/// desktop builds all fall in that set.
///
/// The knowledge was learned once in WaveCrux's hand-rolled AI-key store and
/// stayed there; a suite-wide audit found this package, which SimCrux Pro
/// consumes for PR-annotation credentials, still taking the plugin default.
/// If someone "simplifies" the default back to a bare `FlutterSecureStorage()`
/// the failure is silent and platform-specific — a stored credential simply
/// never comes back — so it is worth a test rather than a comment.
void main() {
  group('kCruxDefaultSecureStorage', () {
    test('opts out of the macOS data-protection keychain', () {
      // Assert on the serialized map rather than the field: `mOptions` is
      // typed as the `AppleOptions` supertype, and the map is what actually
      // crosses the platform channel — so this pins the wire contract.
      expect(
        kCruxDefaultSecureStorage.mOptions
            .toMap()['usesDataProtectionKeychain'],
        'false',
        reason:
            'The data-protection keychain needs a keychain-access-groups '
            'entitlement and a real signing certificate. Leaving this true '
            'breaks credential storage on every ad-hoc-signed build.',
      );
    });

    test(
      'differs from the plugin default, which is what makes it load-bearing',
      () {
        // If this ever fails, the plugin changed its default and the override
        // may no longer be needed — check before deleting it.
        expect(
          MacOsOptions.defaultOptions.toMap()['usesDataProtectionKeychain'],
          'true',
          reason:
              'flutter_secure_storage changed its MacOsOptions default. '
              'Re-evaluate whether crux_secrets still needs to override it.',
        );
      },
    );

    test('the store adopts it when no storage is injected', () {
      // Constructing the default store must not throw, and must be const —
      // the const-ness is what lets hosts declare it in a const override list.
      const store = FlutterSecureStorageSecretStore();
      expect(store, isA<CruxSecretStore>());
    });
  });
}
