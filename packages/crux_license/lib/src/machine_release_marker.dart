// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Pure Dart only: this file is on the `crux_license_core.dart` barrel, which
// the products' headless CLIs link without `dart:ui`, and
// `test/crux_license_core_test.dart` walks that barrel's closure.

// The file marker's collaborators are named publicly and stored privately.
// Not `this._environment`: a private initializing formal is published under
// its private name in tooling that reads parameter names, including the
// api/*.api.txt goldens, and callers pass `environment:`.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_license/src/install_fingerprint.dart';
import 'package:path/path.dart' as p;

/// A note that this machine's seat on a licence was released, left by the
/// product that released it for the other products on the machine.
///
/// ### Why the other products need telling
///
/// The fingerprint is shared, so "Deactivate this machine" releases the
/// machine at the issuer for every product on it. The other products still
/// hold the key, and their next check-in would find the machine unregistered
/// and register it again — undoing the deactivation the user just performed,
/// silently, from a product they were not looking at. The controller consults
/// this marker before it contacts the issuer, and a product that finds its
/// licence released here drops the key instead.
///
/// Matched on the licence **and** the fingerprint: a marker for another
/// licence is somebody else's business, and one for another fingerprint was
/// left before the machine's identity changed. Activating a licence clears its
/// marker, so a key the user pastes after a deactivation is never cleared by
/// the deactivation that preceded it.
///
/// Every implementation fails soft: [wasReleased] answers `false` for anything
/// it cannot read, and a write that fails is a note not left, never an error
/// in the licence flow.
abstract class MachineReleaseMarker {
  /// Note that [fingerprint]'s seat on [licenseId] was released.
  Future<void> markReleased({
    required String licenseId,
    required String fingerprint,
  });

  /// Whether [fingerprint]'s seat on [licenseId] was released and nothing has
  /// activated the licence on this machine since.
  Future<bool> wasReleased({
    required String licenseId,
    required String fingerprint,
  });

  /// Forget any release noted for [licenseId]; called when the licence is
  /// activated again.
  Future<void> clearReleased({required String licenseId});
}

/// No marker at all: nothing is noted and nothing was ever released.
///
/// The controller's default, so a host that has not wired the shared file —
/// a test, or a headless run that never deactivates — keeps the behaviour it
/// had.
class NoMachineReleaseMarker implements MachineReleaseMarker {
  /// Create the no-op marker.
  const NoMachineReleaseMarker();

  @override
  Future<void> markReleased({
    required String licenseId,
    required String fingerprint,
  }) async {}

  @override
  Future<bool> wasReleased({
    required String licenseId,
    required String fingerprint,
  }) async => false;

  @override
  Future<void> clearReleased({required String licenseId}) async {}
}

/// A marker held in memory, for tests: what several controllers over one map
/// see of each other's releases.
class InMemoryMachineReleaseMarker implements MachineReleaseMarker {
  /// Create one, optionally over an existing [released] map.
  InMemoryMachineReleaseMarker([Map<String, String>? released])
    : released = released ?? <String, String>{};

  /// Licence id to the fingerprint whose seat on it was released.
  final Map<String, String> released;

  @override
  Future<void> markReleased({
    required String licenseId,
    required String fingerprint,
  }) async => released[licenseId] = fingerprint;

  @override
  Future<bool> wasReleased({
    required String licenseId,
    required String fingerprint,
  }) async => released[licenseId] == fingerprint;

  @override
  Future<void> clearReleased({required String licenseId}) async =>
      released.remove(licenseId);
}

/// The marker every product on this account shares: `released.json` under
/// [cruxLicenseDirectory].
///
/// ```json
/// {"v": 1, "released": {"<licenseId>": {"fingerprint": "…", "at": "<utc>"}}}
/// ```
///
/// Written whole, write-then-rename, so a product reading while another
/// writes sees the old document or the new one. Entries older than
/// [retention] are dropped whenever the file is written: a release nobody
/// acted on in half a year is one every product on the machine has long
/// since seen or never will, and the file should not grow with every licence
/// the user ever held. A document that cannot be parsed is treated as empty —
/// [wasReleased] answers `false`, and the next write replaces it.
class FileMachineReleaseMarker implements MachineReleaseMarker {
  /// Over the shared directory for [environment] and [operatingSystem], both
  /// injectable for tests; [now] is the clock the entries are stamped and
  /// pruned by.
  FileMachineReleaseMarker({
    Map<String, String>? environment,
    String? operatingSystem,
    DateTime Function() now = DateTime.now,
  }) : _environment = environment,
       _operatingSystem = operatingSystem,
       _now = now;

  /// How long a release is remembered once noted.
  static const Duration retention = Duration(days: 180);

  final Map<String, String>? _environment;
  final String? _operatingSystem;
  final DateTime Function() _now;

  @override
  Future<void> markReleased({
    required String licenseId,
    required String fingerprint,
  }) async {
    try {
      final entries = _prune(await _read());
      entries[licenseId] = <String, Object?>{
        'fingerprint': fingerprint,
        'at': _now().toUtc().toIso8601String(),
      };
      await _write(entries);
    } on Object {
      // Best effort, by contract: a note not left costs the other products
      // one re-registration at their next check-in, which is the state before
      // the marker existed. Failing the deactivation over it would not.
    }
  }

  @override
  Future<bool> wasReleased({
    required String licenseId,
    required String fingerprint,
  }) async {
    try {
      final entry = (await _read())[licenseId];
      return entry != null && entry['fingerprint'] == fingerprint;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> clearReleased({required String licenseId}) async {
    try {
      final entries = await _read();
      if (!entries.containsKey(licenseId)) return;
      entries.remove(licenseId);
      await _write(_prune(entries));
    } on Object {
      // Best effort, as above. The controller also skips the marker on the
      // activation path itself, so a note that could not be cleared cannot
      // undo the key the user just pasted.
    }
  }

  /// The document's entries, keyed by licence id; empty for a missing,
  /// unreadable or malformed file. Throws only for a directory that cannot be
  /// resolved, which every caller catches.
  Future<Map<String, Map<String, Object?>>> _read() async {
    final file = File(_path());
    if (!file.existsSync()) return <String, Map<String, Object?>>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on Object {
      return <String, Map<String, Object?>>{};
    }
    if (decoded is! Map<String, Object?> || decoded['v'] != 1) {
      return <String, Map<String, Object?>>{};
    }
    final released = decoded['released'];
    if (released is! Map<String, Object?>) {
      return <String, Map<String, Object?>>{};
    }
    return <String, Map<String, Object?>>{
      for (final entry in released.entries)
        if (entry.value case final Map<String, Object?> value) entry.key: value,
    };
  }

  Future<void> _write(Map<String, Map<String, Object?>> entries) =>
      writeJsonAtomic(File(_path()), <String, Object?>{
        'v': 1,
        'released': entries,
      });

  /// [entries] without those stamped more than [retention] ago. An entry
  /// whose stamp cannot be read is kept: dropping it would forget a release
  /// on the strength of a typo.
  Map<String, Map<String, Object?>> _prune(
    Map<String, Map<String, Object?>> entries,
  ) {
    final cutoff = _now().toUtc().subtract(retention);
    return <String, Map<String, Object?>>{
      for (final entry in entries.entries)
        if (!_isBefore(entry.value['at'], cutoff)) entry.key: entry.value,
    };
  }

  static bool _isBefore(Object? stamp, DateTime cutoff) {
    if (stamp is! String) return false;
    final at = DateTime.tryParse(stamp);
    return at != null && at.toUtc().isBefore(cutoff);
  }

  String _path() {
    final os = _operatingSystem ?? Platform.operatingSystem;
    final ctx = os == 'windows' ? p.windows : p.posix;
    return ctx.join(
      cruxLicenseDirectory(environment: _environment, operatingSystem: os),
      'released.json',
    );
  }
}
