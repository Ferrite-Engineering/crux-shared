// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Storage key holding the EULA version the user last accepted.
///
/// Fixed for the suite: the four products, the Pro overlays and any future
/// migration tooling agree on this exact string. It sits outside any product's
/// `settings.*` namespace on purpose — acceptance is a property of *this
/// installation on this machine*, not a preference that should travel with a
/// copied settings file. A settings file carried to a second machine must not
/// carry an acceptance the person at that machine never gave.
const String kCruxEulaAcceptedVersionKey = 'eula.acceptedVersion';

/// The persistence seam for the accepted-version record.
///
/// A narrow key/value contract rather than a `SharedPreferences` dependency,
/// for the same two reasons `TelemetryStorage` is shaped this way: each product
/// already owns a preferences layer and should not acquire a second, and a
/// package reaching for a plugin directly would make every acceptance test in
/// it a plugin test. Products bind `cruxEulaStorageProvider` to a short adapter
/// over whatever they already use.
///
/// **The failure direction is the opposite of telemetry's.** Telemetry storage
/// fails soft towards collecting nothing, because the safe answer there is to
/// do less. Here the safe answer is to *ask again*: a read that cannot complete
/// returns `null`, which reads as "never accepted" and shows the dialog. That
/// is an inconvenience when storage is broken, and it is the only behaviour
/// consistent with EULA section 2.1 — the application does not proceed until
/// the agreement is accepted, and an unreadable store is not an acceptance.
///
/// A write that cannot complete is dropped, and the user is asked again on the
/// next launch. Nothing here may throw into the widget tree.
abstract class CruxEulaStorage {
  /// Const constructor for subclasses.
  const CruxEulaStorage();

  /// Returns the stored value for [key], or `null` when nothing is stored.
  Future<String?> read(String key);

  /// Persists [value] under [key].
  Future<void> write(String key, String value);

  /// Deletes whatever is stored under [key], if anything.
  Future<void> remove(String key);
}

/// Puts this installation back to "never accepted", so the agreement is
/// presented again on the next launch.
///
/// A **testing** affordance, surfaced by each product as `--reset-eula`. Once
/// an installation has accepted, the dialog deliberately never returns until
/// `kCruxEulaVersion` changes, which makes the one surface every reviewer needs
/// to eyeball the hardest one to see twice.
///
/// Named for what it does rather than for the flag, because it is also the
/// honest way to undo an acceptance given on someone else's behalf.
Future<void> resetCruxEulaAcceptance(CruxEulaStorage storage) =>
    storage.remove(kCruxEulaAcceptedVersionKey);

/// A [CruxEulaStorage] that keeps values for the life of the process.
///
/// The default binding of `cruxEulaStorageProvider`, and the store every test
/// in this package uses. As a *production* binding it is wrong in exactly one
/// visible way — the agreement is presented on every launch — which is
/// deliberately the loudest failure available that still cannot let an
/// un-accepted build through. A silent default that let the app proceed would
/// be the one bug this package must not have.
class InMemoryCruxEulaStorage extends CruxEulaStorage {
  /// Creates an in-memory store, optionally pre-seeded with [seed] — the test
  /// equivalent of "an installation that accepted on a previous launch".
  InMemoryCruxEulaStorage([Map<String, String>? seed])
    : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  /// The values currently held, so a test can assert what was written without
  /// reaching through a plugin.
  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
