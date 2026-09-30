// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A namespaced key into a [CruxSecretStore].
///
/// Secrets are addressed by `(product, name)` rather than a bare string so
/// two products sharing one OS keychain cannot collide, and so a product's
/// entire secret set can be enumerated and revoked in one call
/// ([CruxSecretStore.deleteAll]).
///
/// The rendered storage key is `crux.<product>.<name>`. Both halves are
/// restricted to `[a-z0-9_]` at construction: the key reaches platform APIs
/// with different escaping rules (Keychain account strings, Windows
/// credential target names, libsecret attribute values), and a permissive
/// key is the kind of thing that works on the development machine and fails
/// on someone else's.
@immutable
class CruxSecretKey {
  /// Creates a key. Throws [ArgumentError] if either half is empty or
  /// contains anything outside `[a-z0-9_]`.
  CruxSecretKey({required this.product, required this.name}) {
    _validate('product', product);
    _validate('name', name);
  }

  static final RegExp _allowed = RegExp(r'^[a-z0-9_]+$');

  static void _validate(String label, String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, label, 'must not be empty');
    }
    if (!_allowed.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        label,
        'must match [a-z0-9_]+ — the key reaches platform credential APIs '
        'whose escaping rules differ',
      );
    }
  }

  /// Owning product, lower-snake (`simcrux`, `lintcrux`).
  final String product;

  /// Secret name within the product, lower-snake
  /// (`pr_annotation_token`, `team_db_password`).
  final String name;

  /// The flat key handed to the platform implementation.
  String get storageKey => 'crux.$product.$name';

  /// The prefix every key of [product] shares — the basis for
  /// [CruxSecretStore.deleteAll].
  static String prefixFor(String product) {
    _validate('product', product);
    return 'crux.$product.';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxSecretKey && other.product == product && other.name == name;

  @override
  int get hashCode => Object.hash(product, name);

  /// Renders the key, never a value — [CruxSecretStore] implementations
  /// log through this and must never log the secret itself.
  @override
  String toString() => 'CruxSecretKey($storageKey)';
}

/// Raised when the platform credential store is unreachable or refuses an
/// operation.
///
/// Deliberately a distinct type rather than a rethrown platform exception:
/// callers routinely want to degrade (run without the credential, prompt
/// the user again) rather than crash, and they cannot pattern-match on
/// `PlatformException` without depending on the platform plugin.
///
/// The [message] is safe to surface to a user and never contains the
/// secret. [cause] carries the original error for diagnostics.
class CruxSecretStoreException implements Exception {
  /// Creates the exception.
  const CruxSecretStoreException(this.message, {this.key, this.cause});

  /// Human-readable, secret-free explanation.
  final String message;

  /// The key being operated on, when the failure was key-scoped.
  final CruxSecretKey? key;

  /// The underlying platform error, if any.
  final Object? cause;

  @override
  String toString() =>
      'CruxSecretStoreException: $message'
      '${key != null ? ' (${key!.storageKey})' : ''}';
}

/// Read/write/delete over the operating system's credential store.
///
/// ### Why this exists
///
/// Every product in the suite eventually needs to persist exactly one class
/// of thing that must not land in `shared_preferences`: a credential the
/// user typed. SimCrux's PR-annotation auth token and the Enterprise
/// shared-team-database password (SimCrux and LintCrux) are the current
/// cases. `shared_preferences` is a plist on macOS, a registry key
/// on Windows and a JSON file on Linux — all world-readable by anything
/// running as the user, which is the wrong place for a token that can push
/// commit statuses to a company's repositories.
///
/// ### Contract
///
/// * [read] returns `null` for an absent key. Absent is not an error.
/// * [write] with a `null` or empty value **deletes** the key rather than
///   storing an empty string, so "clear the field and save" does the
///   obvious thing at every call site instead of leaving an empty secret
///   behind that later reads as "configured".
/// * [delete] on an absent key succeeds silently.
/// * Every method throws [CruxSecretStoreException] — never a raw platform
///   exception — when the backing store itself fails.
///
/// ### Implementations
///
/// * `FlutterSecureStorageSecretStore` — the real one, in this package.
/// * [InMemoryCruxSecretStore] — tests and headless runs.
/// * [UnavailableCruxSecretStore] — the default binding, which fails every
///   call with a clear message. See `cruxSecretStoreProvider` for why the
///   default is loud rather than silently in-memory.
abstract class CruxSecretStore {
  /// Reads the secret at [key], or `null` when nothing is stored.
  Future<String?> read(CruxSecretKey key);

  /// Stores [value] at [key]. A `null` or empty [value] deletes the key.
  Future<void> write(CruxSecretKey key, String? value);

  /// Deletes [key]. Succeeds when the key is already absent.
  Future<void> delete(CruxSecretKey key);

  /// Deletes every key belonging to [product]. Used by "sign out" /
  /// "forget my credentials" affordances.
  Future<void> deleteAll(String product);
}

/// In-memory [CruxSecretStore] for tests and headless runs.
///
/// Not persistent and not secure — the contents live in a plain [Map] for
/// the lifetime of the object. That is the point: a test must never touch
/// the developer's real keychain, and a CI runner has no unlocked keychain
/// to touch.
class InMemoryCruxSecretStore implements CruxSecretStore {
  /// Creates an empty store, optionally seeded with [initial].
  InMemoryCruxSecretStore([Map<String, String>? initial])
    : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  /// Snapshot of the stored keys, for test assertions. Values are
  /// deliberately not exposed as a group — assert on [read] instead.
  Iterable<String> get storedKeys => List<String>.unmodifiable(_values.keys);

  @override
  Future<String?> read(CruxSecretKey key) async => _values[key.storageKey];

  @override
  Future<void> write(CruxSecretKey key, String? value) async {
    if (value == null || value.isEmpty) {
      _values.remove(key.storageKey);
      return;
    }
    _values[key.storageKey] = value;
  }

  @override
  Future<void> delete(CruxSecretKey key) async {
    _values.remove(key.storageKey);
  }

  @override
  Future<void> deleteAll(String product) async {
    final prefix = CruxSecretKey.prefixFor(product);
    _values.removeWhere((k, _) => k.startsWith(prefix));
  }
}

/// The default binding: every operation throws.
///
/// A host that has not registered a real store is misconfigured, and the
/// two plausible silent defaults are both worse than failing:
///
/// * An in-memory default would accept a token, appear to save it, and lose
///   it on restart — the user would re-enter it forever and never be told
///   why.
/// * A no-op default would silently discard it and report success.
///
/// So the unbound default is loud. [read] is the one exception: it returns
/// `null` rather than throwing, because "is a credential configured?" is a
/// question startup code asks before the user has done anything, and the
/// honest answer in an unconfigured host is "no".
class UnavailableCruxSecretStore implements CruxSecretStore {
  /// Creates the store.
  const UnavailableCruxSecretStore();

  static const String _explanation =
      'No CruxSecretStore is registered. The host application must override '
      'cruxSecretStoreProvider (with FlutterSecureStorageSecretStore in an '
      'app, or InMemoryCruxSecretStore in a test) before any credential is '
      'read or written.';

  @override
  Future<String?> read(CruxSecretKey key) async => null;

  @override
  Future<void> write(CruxSecretKey key, String? value) async {
    throw CruxSecretStoreException(_explanation, key: key);
  }

  @override
  Future<void> delete(CruxSecretKey key) async {
    throw CruxSecretStoreException(_explanation, key: key);
  }

  @override
  Future<void> deleteAll(String product) async {
    throw const CruxSecretStoreException(_explanation);
  }
}
