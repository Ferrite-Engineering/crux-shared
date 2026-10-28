// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The file memory's collaborators are named publicly and stored privately.
// Not `this._environment`: a private initializing formal is published under
// its private name in tooling that reads parameter names, including the
// api/*.api.txt goldens, and callers pass `environment:`.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_license/src/install_fingerprint.dart';
import 'package:path/path.dart' as p;

/// Which one-time licence notices this machine has already shown.
///
/// The drop to Open Core at the end of a licence's grace, or of an
/// evaluation, is said once: shown on the launch where it happens and not
/// again, because a customer who has decided not to renew should not be told
/// so every morning. Keyed by `CruxLicenseExpiryNotice.identity`, so a
/// renewed licence that lapses again later is a new notice.
///
/// Every implementation fails soft: [wasShown] answers `false` for anything
/// it cannot read, which shows the notice again rather than never.
abstract class LicenseNoticeMemory {
  /// Whether the notice named [identity] has been shown.
  Future<bool> wasShown(String identity);

  /// Record that the notice named [identity] has been shown.
  Future<void> markShown(String identity);
}

/// A memory held in memory: the default, and what tests use. Remembers for
/// the life of the process, so without a host-wired file a one-time notice
/// is once per launch.
class InMemoryLicenseNoticeMemory implements LicenseNoticeMemory {
  /// Create one, optionally over an existing [shown] set.
  InMemoryLicenseNoticeMemory([Set<String>? shown])
    : shown = shown ?? <String>{};

  /// The identities shown so far.
  final Set<String> shown;

  @override
  Future<bool> wasShown(String identity) async => shown.contains(identity);

  @override
  Future<void> markShown(String identity) async => shown.add(identity);
}

/// The memory every product on this account shares: `notices.json` under
/// [cruxLicenseDirectory].
///
/// ```json
/// {"v": 1, "shown": {"<identity>": "<utc>"}}
/// ```
///
/// Shared because a suite licence lapses for every product at once, and one
/// notice means one, not one per product. Entries older than [retention] are
/// dropped whenever the file is written. A document that cannot be parsed is
/// treated as empty, and the next write replaces it.
class FileLicenseNoticeMemory implements LicenseNoticeMemory {
  /// Over the shared directory for [environment] and [operatingSystem], both
  /// injectable for tests; [now] stamps and prunes the entries.
  FileLicenseNoticeMemory({
    Map<String, String>? environment,
    String? operatingSystem,
    DateTime Function() now = DateTime.now,
  }) : _environment = environment,
       _operatingSystem = operatingSystem,
       _now = now;

  /// How long a shown notice is remembered.
  static const Duration retention = Duration(days: 400);

  final Map<String, String>? _environment;
  final String? _operatingSystem;
  final DateTime Function() _now;

  @override
  Future<bool> wasShown(String identity) async {
    try {
      return (await _read()).containsKey(identity);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> markShown(String identity) async {
    try {
      final cutoff = _now().toUtc().subtract(retention);
      final shown = <String, Object?>{
        for (final entry in (await _read()).entries)
          if (!_isBefore(entry.value, cutoff)) entry.key: entry.value,
      };
      shown[identity] = _now().toUtc().toIso8601String();
      await writeJsonAtomic(File(_path()), <String, Object?>{
        'v': 1,
        'shown': shown,
      });
    } on Object {
      // Best effort, by contract: a notice not remembered is shown once more.
    }
  }

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
    final shown = decoded['shown'];
    return shown is Map<String, Object?>
        ? Map<String, Object?>.of(shown)
        : <String, Object?>{};
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
      'notices.json',
    );
  }
}
