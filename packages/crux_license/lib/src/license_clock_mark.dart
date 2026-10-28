// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Pure Dart only: this file is on the `crux_license_core.dart` barrel, which
// the products' headless CLIs link without `dart:ui`, and
// `test/crux_license_core_test.dart` walks that barrel's closure.

// The file mark's collaborators are named publicly and stored privately.
// Not `this._environment`: a private initializing formal is published under
// its private name in tooling that reads parameter names, including the
// api/*.api.txt goldens, and callers pass `environment:`.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_license/src/install_fingerprint.dart';
import 'package:path/path.dart' as p;

/// How far an evaluation's clock may read behind the latest time the app has
/// seen before the evaluation is treated as ended.
///
/// Wide enough for what an honest machine does to its clock: an NTP
/// correction, a time zone set wrong and then right, a laptop whose battery
/// ran flat. Narrow enough that winding the clock back a week to stretch an
/// evaluation does not work.
const Duration kEvaluationClockTolerance = Duration(hours: 24);

/// The latest time the app has seen while an evaluation licence was in force:
/// its clock high-water mark.
///
/// ### Why an evaluation needs one
///
/// On a machine that cannot reach the issuer, expiry is judged against the
/// machine's own clock, and nothing else notices a clock that has been set
/// back. For a paid licence that is the right trade: a wrong clock must never
/// take a paying customer's tier away. An evaluation's end date is the
/// agreement, so for an evaluation the controller keeps this mark, starting
/// from the credential's issue time, and treats a clock that reads earlier
/// than it by more than [kEvaluationClockTolerance] as the end of the
/// evaluation (`CruxLicenseStatus.clockSetBack`).
///
/// Keyed by licence id, so a mark left by one evaluation never judges another
/// licence. Every implementation fails soft: [read] answers `null` for
/// anything it cannot read, and a write that fails is a mark not moved, never
/// an error in the licence flow. The issue time still applies without it.
abstract class LicenseClockMark {
  /// The mark recorded for [licenseId], or `null` when there is none.
  Future<DateTime?> read({required String licenseId});

  /// Move the mark for [licenseId] to [at], if [at] is later than the mark.
  /// A mark never moves backwards.
  Future<void> advance({required String licenseId, required DateTime at});
}

/// A mark held in memory: what the controller uses when the host wires none,
/// and what tests use.
///
/// Survives for the life of the process only, so a host that wants the check
/// to hold across launches wires [FileLicenseClockMark].
class InMemoryLicenseClockMark implements LicenseClockMark {
  /// Create one, optionally over an existing [marks] map.
  InMemoryLicenseClockMark([Map<String, DateTime>? marks])
    : marks = marks ?? <String, DateTime>{};

  /// Licence id to its mark.
  final Map<String, DateTime> marks;

  @override
  Future<DateTime?> read({required String licenseId}) async => marks[licenseId];

  @override
  Future<void> advance({
    required String licenseId,
    required DateTime at,
  }) async {
    final held = marks[licenseId];
    if (held == null || at.isAfter(held)) marks[licenseId] = at.toUtc();
  }
}

/// The mark every product on this account shares: `clock.json` under
/// [cruxLicenseDirectory].
///
/// ```json
/// {"v": 1, "marks": {"<licenseId>": "<utc>"}}
/// ```
///
/// Shared because an evaluation is usually a suite licence, and the latest
/// time any product saw is the latest time the machine saw. Written whole,
/// write-then-rename, so a product reading while another writes sees the old
/// document or the new one. A document that cannot be parsed is treated as
/// empty, and the next write replaces it.
class FileLicenseClockMark implements LicenseClockMark {
  /// Over the shared directory for [environment] and [operatingSystem], both
  /// injectable for tests.
  FileLicenseClockMark({
    Map<String, String>? environment,
    String? operatingSystem,
  }) : _environment = environment,
       _operatingSystem = operatingSystem;

  final Map<String, String>? _environment;
  final String? _operatingSystem;

  @override
  Future<DateTime?> read({required String licenseId}) async {
    try {
      final stamp = (await _read())[licenseId];
      return stamp is String ? DateTime.tryParse(stamp)?.toUtc() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> advance({
    required String licenseId,
    required DateTime at,
  }) async {
    try {
      final marks = await _read();
      final held = marks[licenseId];
      final heldAt = held is String ? DateTime.tryParse(held) : null;
      if (heldAt != null && !at.isAfter(heldAt)) return;
      marks[licenseId] = at.toUtc().toIso8601String();
      await writeJsonAtomic(File(_path()), <String, Object?>{
        'v': 1,
        'marks': marks,
      });
    } on Object {
      // Best effort, by contract: a mark not moved costs the clock check
      // this launch's time, and the issue time still applies.
    }
  }

  /// The document's marks, keyed by licence id; empty for a missing,
  /// unreadable or malformed file. Throws only for a directory that cannot be
  /// resolved, which every caller catches.
  Future<Map<String, Object?>> _read() async {
    final file = File(_path());
    if (!file.existsSync()) return <String, Object?>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on Object {
      return <String, Object?>{};
    }
    if (decoded is! Map<String, Object?> || decoded['v'] != 1) {
      return <String, Object?>{};
    }
    final marks = decoded['marks'];
    return marks is Map<String, Object?>
        ? Map<String, Object?>.of(marks)
        : <String, Object?>{};
  }

  String _path() {
    final os = _operatingSystem ?? Platform.operatingSystem;
    final ctx = os == 'windows' ? p.windows : p.posix;
    return ctx.join(
      cruxLicenseDirectory(environment: _environment, operatingSystem: os),
      'clock.json',
    );
  }
}
