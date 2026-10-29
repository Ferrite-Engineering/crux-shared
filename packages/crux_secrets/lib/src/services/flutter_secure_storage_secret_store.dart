// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_secrets/src/secret_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The `flutter_secure_storage` configuration every crux product's secret
/// store uses by default.
///
/// Exists as a named constant rather than an inline default so a test can pin
/// [MacOsOptions.usesDataProtectionKeychain] — see the class doc on
/// [FlutterSecureStorageSecretStore] for why that flag is load-bearing. The
/// plugin's own default for it is `true`, which is the configuration that
/// fails on ad-hoc-signed builds, so this must never be replaced by a bare
/// `FlutterSecureStorage()`.
const FlutterSecureStorage kCruxDefaultSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

/// [CruxSecretStore] backed by `package:flutter_secure_storage`.
///
/// Maps to Keychain on macOS/iOS, the DPAPI-backed credential store on
/// Windows, and libsecret on Linux. Every platform error is translated into
/// [CruxSecretStoreException] so callers never have to import the plugin to
/// handle failure.
///
/// ### Linux needs libsecret present
///
/// On Linux, `flutter_secure_storage` talks to libsecret, which needs a
/// running secret service (gnome-keyring, KWallet with the bridge, …). A
/// headless CI container typically has none, and every call fails. That is
/// reported honestly through [CruxSecretStoreException] rather than being
/// papered over with a plaintext fallback — a credential store that
/// silently degrades to a file is not a credential store. Hosts that must
/// keep working there should bind [InMemoryCruxSecretStore] and re-prompt.
///
/// Once a call has found no secret service at all, every later call in the
/// process fails the same way without reaching the plugin; see
/// [_missingSecretService].
///
/// ### macOS uses the legacy file-based login keychain
///
/// The default binds `MacOsOptions(usesDataProtectionKeychain: false)` rather
/// than taking the plugin's default, and that is load-bearing rather than
/// incidental. The iOS-style data-protection keychain requires a
/// `keychain-access-groups` entitlement plus signing with a real development
/// certificate, which would force *every* macOS build in the suite to carry a
/// provisioned signing identity — including certless ad-hoc CI
/// integration-test builds and any contributor's local `flutter run`. The
/// file-based login keychain works under plain ad-hoc / "Sign to Run Locally"
/// signing on these non-sandboxed apps, so a stored credential persists
/// without gating builds on Apple-team membership.
///
/// This was learned the hard way in WaveCrux's hand-rolled AI-key store and
/// lived only there until a suite-wide audit found that this package — the one
/// every other product consumes — was still taking the plugin default. Do not
/// "simplify" it back to a bare `FlutterSecureStorage()`.
class FlutterSecureStorageSecretStore implements CruxSecretStore {
  /// Creates the store. [storage] is injectable for tests that want to
  /// exercise the error-translation paths without a keychain.
  const FlutterSecureStorageSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? kCruxDefaultSecureStorage;

  final FlutterSecureStorage _storage;

  /// The error from the first call that found no secret service to talk to,
  /// kept for the life of the process.
  ///
  /// On Linux every call asks libsecret to reach the secret service over the
  /// DBus session bus. A session with none (a farm job displayed on another
  /// machine, a minimal install) fails each call the same way, and the plugin
  /// prints a warning for each. The licence controller alone makes several
  /// calls per check, so such a session filled its terminal with hundreds of
  /// identical lines. After the first, calls fail at once with the same cause
  /// and never reach the plugin. A secret service that starts later is found
  /// at the next launch. A locked keyring is not this: it can be unlocked,
  /// so it is asked again every time.
  static Object? _missingSecretService;

  /// Forgets [_missingSecretService], for tests that stage a session with no
  /// secret service.
  @visibleForTesting
  static void debugForgetMissingSecretService() => _missingSecretService = null;

  /// Whether [error] is the plugin reporting that libsecret could not reach
  /// or open the secret service, which it prefixes with the libsecret call
  /// that failed.
  static bool _isMissingSecretService(Object error) =>
      error is PlatformException &&
      (error.message ?? '').startsWith('secret_service_get_sync');

  /// Runs [call], translating every failure into a [CruxSecretStoreException]
  /// with [message] and [key].
  Future<T> _guard<T>(
    Future<T> Function() call,
    String message, {
    CruxSecretKey? key,
  }) async {
    final missing = _missingSecretService;
    if (missing != null) {
      throw CruxSecretStoreException(message, key: key, cause: missing);
    }
    try {
      return await call();
    } on Object catch (e) {
      if (_isMissingSecretService(e)) _missingSecretService = e;
      throw CruxSecretStoreException(message, key: key, cause: e);
    }
  }

  @override
  Future<String?> read(CruxSecretKey key) => _guard(
    () => _storage.read(key: key.storageKey),
    'Could not read a stored credential from the system keychain.',
    key: key,
  );

  @override
  Future<void> write(CruxSecretKey key, String? value) {
    // Empty means "cleared", not "an empty secret" — otherwise a user who
    // blanks the field and saves leaves a stored empty string behind that
    // every `!= null` check downstream reads as "still configured".
    if (value == null || value.isEmpty) {
      return delete(key);
    }
    return _guard(
      () => _storage.write(key: key.storageKey, value: value),
      'Could not save a credential to the system keychain.',
      key: key,
    );
  }

  @override
  Future<void> delete(CruxSecretKey key) => _guard(
    () => _storage.delete(key: key.storageKey),
    'Could not remove a credential from the system keychain.',
    key: key,
  );

  @override
  Future<void> deleteAll(String product) {
    final prefix = CruxSecretKey.prefixFor(product);
    return _guard(() async {
      // Scoped to this product's prefix — never `deleteAll()`, which would
      // wipe every other crux product's credentials out of the shared
      // keychain namespace.
      final all = await _storage.readAll();
      for (final k in all.keys.where((k) => k.startsWith(prefix))) {
        await _storage.delete(key: k);
      }
    }, 'Could not clear stored credentials from the system keychain.');
  }
}
