// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_secrets/crux_secrets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one real [CruxSecretStore] backend, driven through the platform
/// channel it actually talks to.
///
/// Nothing here fakes [FlutterSecureStorageSecretStore] or the plugin class it
/// wraps. The keychain is replaced at the lowest seam Dart can reach — the
/// `plugins.it_nomads.com/flutter_secure_storage` method channel — so every
/// byte of this package and of the plugin's Dart side runs as it does in a
/// product. That matters because the package used to report two-thirds
/// coverage on the strength of its in-memory fake while this class, the only
/// one that ever touches a user's keychain, sat at one line in eighteen.
///
/// What a keychain does that the fake cannot: refuse. It denies access (a
/// locked login keychain, a user who clicks "Deny"), it is absent (Linux with
/// no secret service), it answers with the wrong type, and it fails half-way
/// through a multi-key operation. Each of those must reach the caller as a
/// [CruxSecretStoreException] — never a raw platform error, never an `Error`,
/// and never with the secret in the message.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _Keychain keychain;

  setUp(() {
    keychain = _Keychain();
    messenger.setMockMethodCallHandler(channel, keychain.handle);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  final token = CruxSecretKey(product: 'simcrux', name: 'pr_annotation_token');
  final password = CruxSecretKey(product: 'simcrux', name: 'team_db_password');
  const store = FlutterSecureStorageSecretStore();

  group('the contract, against a keychain that answers', () {
    test('an absent key reads as null, not as an error', () async {
      expect(await store.read(token), isNull);
      expect(keychain.calls.single.method, 'read');
      expect(keychain.calls.single.key, 'crux.simcrux.pr_annotation_token');
    });

    test('a written value reads back under the namespaced key', () async {
      await store.write(token, 'ghp_example');

      expect(keychain.items, {
        'crux.simcrux.pr_annotation_token': 'ghp_example',
      });
      expect(await store.read(token), 'ghp_example');
    });

    test('writing empty or null deletes rather than storing it', () async {
      // A user who blanks the field and saves must not leave an empty string
      // behind that every `!= null` check downstream reads as "configured".
      for (final cleared in <String?>['', null]) {
        keychain.items['crux.simcrux.pr_annotation_token'] = 'old';
        keychain.calls.clear();

        await store.write(token, cleared);

        expect(keychain.items, isEmpty, reason: 'value: ${cleared ?? 'null'}');
        expect(
          keychain.calls.map((c) => c.method),
          <String>['delete'],
          reason: 'no empty write may reach the keychain',
        );
      }
    });

    test('deleting an absent key succeeds silently', () async {
      await store.delete(token);
      expect(keychain.calls.single.method, 'delete');
    });

    test('deleteAll clears one product and nothing else', () async {
      // The keychain is shared by every crux product and by anything else
      // the plugin stores; "forget my credentials" in SimCrux must not sign
      // the user out of LintCrux.
      keychain.items.addAll(<String, String>{
        'crux.simcrux.pr_annotation_token': 'a',
        'crux.simcrux.team_db_password': 'b',
        'crux.lintcrux.team_db_password': 'c',
        'crux.simcrux_ci.token': 'd',
        'unrelated': 'e',
      });

      await store.deleteAll('simcrux');

      expect(
        keychain.items.keys,
        unorderedEquals(<String>[
          'crux.lintcrux.team_db_password',
          'crux.simcrux_ci.token',
          'unrelated',
        ]),
      );
      expect(
        keychain.calls.map((c) => c.method),
        isNot(contains('deleteAll')),
        reason: "the plugin's deleteAll wipes every product's keys",
      );
    });

    test('deleteAll on an empty keychain answer does nothing', () async {
      // The plugin turns a null readAll answer into an empty map; nothing is
      // deleted and nothing throws.
      keychain.readAllAnswer = () => null;

      await store.deleteAll('simcrux');

      expect(keychain.calls.map((c) => c.method), <String>['readAll']);
    });

    test('on macOS the default store asks for the login keychain', () async {
      // The iOS-style data-protection keychain needs a signing identity every
      // ad-hoc and CI build in the suite lacks, and there a stored credential
      // simply never comes back. The constant is pinned elsewhere; this pins
      // that the store sends it on every call.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      await store.write(token, 'x');
      await store.read(token);
      await store.delete(token);
      await store.deleteAll('simcrux');

      expect(keychain.calls, hasLength(4));
      for (final call in keychain.calls) {
        expect(
          call.options['usesDataProtectionKeychain'],
          'false',
          reason: '${call.method} must not use the data-protection keychain',
        );
      }
    });
  });

  group('a keychain that refuses', () {
    /// Every way a native keychain call fails that a test can stage for
    /// every operation: a `PlatformException` (locked keychain, denied
    /// prompt, no secret service) and a missing plugin (no handler at all).
    final refusals = <String, void Function()>{
      'access denied (macOS errSecAuthFailed)': () =>
          keychain.failWith = PlatformException(
            code: '-25293',
            message: 'The user name or passphrase you entered is not correct.',
          ),
      'no secret service (Linux libsecret)': () =>
          keychain.failWith = PlatformException(
            code: 'Libsecret error',
            message: 'Failed to unlock the keyring',
          ),
      'no plugin registered at all': () =>
          messenger.setMockMethodCallHandler(channel, null),
    };

    for (final entry in refusals.entries) {
      group(entry.key, () {
        setUp(entry.value);

        test('read', () async {
          await _expectStoreException(() => store.read(token), key: token);
        });

        test('write', () async {
          await _expectStoreException(
            () => store.write(password, 'hunter2-the-secret'),
            key: password,
            secret: 'hunter2-the-secret',
          );
        });

        test('delete', () async {
          await _expectStoreException(() => store.delete(token), key: token);
        });

        test('deleteAll', () async {
          await _expectStoreException(() => store.deleteAll('simcrux'));
        });
      });
    }

    test('a read answered with the wrong type', () async {
      // The plugin casts the native answer; a failed cast is a TypeError, an
      // Error that walks through every `on Exception` above it.
      keychain.wrongType = true;
      await _expectStoreException(() => store.read(token), key: token);
    });

    test('a readAll answered with the wrong type', () async {
      keychain.wrongType = true;
      await _expectStoreException(() => store.deleteAll('simcrux'));
    });

    test('a failure half-way through deleteAll is reported', () async {
      // readAll succeeds, the first delete succeeds, the second is refused.
      // The caller is told; a "forget my credentials" that silently left one
      // behind would be reported as done.
      keychain.items.addAll(<String, String>{
        'crux.simcrux.a': '1',
        'crux.simcrux.b': '2',
      });
      keychain.failDeleteAfter = 1;

      await _expectStoreException(() => store.deleteAll('simcrux'));
      expect(keychain.items, hasLength(1), reason: 'one was deleted');
    });

    test('the platform error is kept as the cause, for diagnostics', () async {
      final denied = PlatformException(code: '-25293', message: 'denied');
      keychain.failWith = denied;

      Object? caught;
      try {
        await store.read(token);
      } on CruxSecretStoreException catch (e) {
        caught = e.cause;
      }

      // The exception crossed the channel codec, so it is a copy; what it
      // says is what support needs.
      expect(
        caught,
        isA<PlatformException>()
            .having((e) => e.code, 'code', denied.code)
            .having((e) => e.message, 'message', denied.message),
      );
    });
  });

  group('the provider default', () {
    test('is loud, not a silent in-memory store', () async {
      // A host that forgot to bind a real store must not accept a token,
      // appear to save it, and lose it at restart.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final unbound = container.read(cruxSecretStoreProvider);

      expect(unbound, isA<UnavailableCruxSecretStore>());
      expect(await unbound.read(token), isNull);
      await expectLater(
        unbound.write(token, 'x'),
        throwsA(isA<CruxSecretStoreException>()),
      );
    });
  });
}

/// Run [action], which must fail with a [CruxSecretStoreException] — an
/// `Exception` an `on Exception` handler catches — naming [key] when given,
/// and never carrying [secret] anywhere a log or a dialog could show it.
Future<void> _expectStoreException(
  Future<Object?> Function() action, {
  CruxSecretKey? key,
  String? secret,
}) async {
  Object? thrown;
  try {
    await action();
  } on Object catch (error) {
    thrown = error;
  }

  expect(
    thrown,
    isA<CruxSecretStoreException>(),
    reason:
        'got ${thrown.runtimeType}: a raw platform error or an Error '
        'escapes the callers, which catch CruxSecretStoreException',
  );
  expect(thrown, isA<Exception>());
  final exception = thrown! as CruxSecretStoreException;
  expect(exception.key, key);
  expect(exception.message, isNotEmpty);
  if (secret != null) {
    expect(exception.message, isNot(contains(secret)));
    expect(exception.toString(), isNot(contains(secret)));
  }
}

/// One call the Dart side made across the channel.
class _Call {
  _Call(this.method, this.key, this.options);

  final String method;
  final String? key;
  final Map<Object?, Object?> options;
}

/// The native side of the plugin, as far as the channel can tell: a keychain
/// that stores, answers, and — when told to — refuses.
class _Keychain {
  final Map<String, String> items = <String, String>{};
  final List<_Call> calls = <_Call>[];

  /// Thrown from every call when set.
  PlatformException? failWith;

  /// Answer `read` and `readAll` with a value of a type the Dart side does
  /// not expect. (`write` and `delete` answer nothing, so there is no type to
  /// get wrong.)
  bool wrongType = false;

  /// Refuse every `delete` after this many have succeeded.
  int? failDeleteAfter;

  /// What `readAll` answers; defaults to the stored items.
  Object? Function()? readAllAnswer;

  var _deletes = 0;

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    final key = args['key'] as String?;
    calls.add(
      _Call(
        call.method,
        key,
        (args['options'] as Map<Object?, Object?>?) ?? const {},
      ),
    );
    final failure = failWith;
    if (failure != null) throw failure;
    if (wrongType && call.method == 'read') return <String, Object?>{};
    if (wrongType && call.method == 'readAll') return 'not a map';
    switch (call.method) {
      case 'read':
        return items[key];
      case 'write':
        items[key!] = args['value']! as String;
        return null;
      case 'delete':
        final limit = failDeleteAfter;
        if (limit != null && _deletes >= limit) {
          throw PlatformException(code: '-25308', message: 'interaction');
        }
        _deletes++;
        items.remove(key);
        return null;
      case 'readAll':
        final answer = readAllAnswer;
        return answer != null ? answer() : Map<String, String>.of(items);
    }
    throw MissingPluginException(call.method);
  }
}
