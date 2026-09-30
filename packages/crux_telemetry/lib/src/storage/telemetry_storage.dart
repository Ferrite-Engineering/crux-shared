// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/models/telemetry_consent_state.dart';

/// Storage key holding the [TelemetryConsentState] name.
///
/// Fixed by the suite spec — the four products and any future migration
/// tooling agree on this exact string, so it is not a detail to tidy. The key
/// lives here rather than in a product's adapter for exactly that reason.
const String kTelemetryConsentKey = 'telemetry.consent';

/// Storage key holding the installation id.
///
/// Beside [kTelemetryConsentKey] and outside any product's `settings.*`
/// namespace for the same reason: this identifies *this copy of the app on
/// this machine*, not the person using it, and it must not travel with a
/// copied settings file.
const String kTelemetryInstallationIdKey = 'telemetry.installationId';

/// The persistence seam for the two per-installation telemetry values —
/// the consent decision and the installation id.
///
/// A narrow key/value contract rather than a `SharedPreferences` dependency,
/// for two reasons. The suite's products already own a preferences layer each
/// and should not end up with two; and a package that reached for
/// `SharedPreferences` directly would make every consent test in it a plugin
/// test. Products bind `telemetryStorageProvider` to a four-line adapter over
/// whatever they already use.
///
/// Implementations must **fail soft**: a read that cannot complete returns
/// `null` (which the consent store reads as "never answered", never as
/// consent) and a write that cannot complete is dropped. Nothing here may
/// throw into the telemetry graph.
abstract class TelemetryStorage {
  /// Const constructor for subclasses.
  const TelemetryStorage();

  /// Returns the stored value for [key], or `null` when nothing is stored.
  Future<String?> read(String key);

  /// Persists [value] under [key].
  Future<void> write(String key, String value);

  /// Deletes whatever is stored under [key], if anything.
  ///
  /// Removing a key is **not** the same as writing an empty string: the
  /// consent store distinguishes "nothing stored" (never answered — the state
  /// that mounts the disclosure) from every stored value, and only an actual
  /// delete can put an installation back in the first.
  ///
  /// Fails soft like the rest of this contract. A delete that cannot complete
  /// leaves the value in place, and the caller finds out by the disclosure not
  /// appearing rather than by an exception.
  Future<void> remove(String key);
}

/// Puts this installation back to "never answered", so the first-launch
/// disclosure mounts again on the next launch.
///
/// A **testing** affordance, surfaced by each product as
/// `--reset-telemetry-consent`. It exists because once an installation has
/// answered, the disclosure deliberately never returns and there is no
/// re-prompt path, which makes the surface everyone most needs to eyeball the
/// surface hardest to see twice.
///
/// Deletes the consent decision and **nothing else** — the installation id
/// survives on purpose. Re-minting it would make every reset look like a new
/// installation to the dataset, which is both a worse test (real first runs
/// are rare) and a slow leak of junk ids into whichever dataset the build
/// points at. A tester who genuinely wants a fresh identity can delete
/// [kTelemetryInstallationIdKey] as a separate, deliberate act.
Future<void> resetTelemetryConsent(TelemetryStorage storage) =>
    storage.remove(kTelemetryConsentKey);

/// A [TelemetryStorage] that keeps values for the life of the process.
///
/// The default binding of `telemetryStorageProvider`, and the store every test
/// in this package uses. As a *production* binding it is wrong in exactly one
/// visible way — the disclosure re-prompts on every launch, and the
/// installation id is re-minted each session — which is deliberately the
/// loudest failure available that still cannot break a feature flow. Telemetry
/// code does not get to throw at wiring the way `crux_updates`' config
/// provider does.
class InMemoryTelemetryStorage extends TelemetryStorage {
  /// Creates an in-memory store, optionally pre-seeded with [seed] — the test
  /// equivalent of "an installation that already answered on a previous
  /// launch".
  InMemoryTelemetryStorage([Map<String, String>? seed])
    : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  /// The values currently held. Exposed so a test can assert what was written
  /// without reaching through a plugin.
  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
