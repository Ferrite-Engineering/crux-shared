// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:isolate';

import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Opens [path] on a second, wholly independent connection and returns the
/// `user_version` it sees once the open succeeds.
///
/// **Runs in its own isolate, deliberately — this is the point of the
/// helper.** `sqflite_common`'s open path serializes every open of the same
/// path *string* through a process-global, in-isolate `Lock`
/// (`sqflite_common`'s `factory_mixin.dart`, its per-path `_NamedLock`), so
/// two opens issued from the *same* isolate never contend for the file at
/// all — the second one simply queues on that Dart-level lock and waits its
/// turn, which proves nothing about `busy_timeout` or SQLite's own file
/// locking. A second isolate holds none of that static state (Dart isolates
/// share no mutable memory), so it opens a genuinely independent native
/// SQLite connection — which is what a second real *process* actually is,
/// and a second real process is the live scenario this guards: LintCrux's
/// `push-trends` CLI opening the same `trends.db` the GUI has open.
///
/// [busyTimeoutMs] mirrors `kCruxSqliteBusyTimeout` (5000 ms) by value rather
/// than by importing it, so this probe carries no dependency on whatever
/// store is under test and can be pointed at any Crux SQLite file.
///
/// A caller synchronizes its timing against whatever is holding the file
/// open by watching for an independent, filesystem-visible side effect —
/// see `crux_open_policy_concurrency_test.dart`'s pattern of a deliberately
/// slow test migration writing a sentinel file the instant it acquires the
/// exclusive lock, which this isolate cannot see any other way (no shared
/// memory to poll).
Future<int> cruxOpenSecondConnectionVersion(
  String path, {
  int busyTimeoutMs = 5000,
}) {
  return Isolate.run(() async {
    ffi.sqfliteFfiInit();
    final db = await ffi.databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA busy_timeout = $busyTimeoutMs'),
      ),
    );
    try {
      return await db.getVersion();
    } finally {
      await db.close();
    }
  });
}
