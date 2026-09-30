// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:test/test.dart';

/// A `DatabaseException` with a result code and message we choose, so the
/// triage table can be exercised against every code that matters rather than
/// only the two a temp file happens to produce.
class _FakeDbException extends DatabaseException {
  // The super parameter is private (`_message`), so its name cannot be
  // matched here.
  // ignore: matching_super_parameters
  _FakeDbException(super.message, this._resultCode);

  final int? _resultCode;

  @override
  int? getResultCode() => _resultCode;

  @override
  Object? get result => null;
}

void main() {
  group('isSqliteCorruption says yes to damaged bytes', () {
    test('SQLITE_CORRUPT (11)', () {
      expect(isSqliteCorruption(_FakeDbException('boom', 11)), isTrue);
    });

    test('SQLITE_NOTADB (26)', () {
      expect(isSqliteCorruption(_FakeDbException('boom', 26)), isTrue);
    });

    test('an EXTENDED corrupt code — the primary code is the low byte', () {
      // SQLITE_CORRUPT_VTAB = 11 | (1 << 8) = 267. sqflite_common_ffi returns
      // extended codes, so masking is not optional.
      expect(isSqliteCorruption(_FakeDbException('boom', 267)), isTrue);
      // SQLITE_CORRUPT_SEQUENCE = 11 | (2 << 8) = 523.
      expect(isSqliteCorruption(_FakeDbException('boom', 523)), isTrue);
    });

    test('the canonical message phrases, when the code cannot be parsed', () {
      // getResultCode() parses the native message and can come back null.
      const phrases = [
        'file is not a database',
        'file is encrypted or is not a database',
        'database disk image is malformed',
      ];
      for (final phrase in phrases) {
        expect(
          isSqliteCorruption(_FakeDbException(phrase, null)),
          isTrue,
          reason: phrase,
        );
      }
    });
  });

  group('isSqliteCorruption says no to a file that is FINE — the exclusion is '
      'the whole point', () {
    // Every one of these describes a healthy file, and every one of them used
    // to reach a handler that deleted it.
    const healthy = <String, int>{
      'SQLITE_BUSY': 5,
      'SQLITE_LOCKED': 6,
      'SQLITE_READONLY': 8,
      'SQLITE_CANTOPEN': 14,
    };

    for (final entry in healthy.entries) {
      test('${entry.key} (${entry.value}) is not corruption', () {
        expect(
          isSqliteCorruption(
            _FakeDbException('database is locked', entry.value),
          ),
          isFalse,
        );
      });

      test('${entry.key} stays not-corruption at its extended codes', () {
        // SQLITE_BUSY_SNAPSHOT, SQLITE_READONLY_DBMOVED, SQLITE_CANTOPEN_ISDIR…
        for (var ext = 1; ext <= 5; ext++) {
          expect(
            isSqliteCorruption(
              _FakeDbException('busy', entry.value | (ext << 8)),
            ),
            isFalse,
            reason: '${entry.key} extended $ext',
          );
        }
      });
    }

    test('a SQLITE_BUSY message mentioning a database is not corruption', () {
      expect(
        isSqliteCorruption(
          _FakeDbException('database is locked (code 5 SQLITE_BUSY)', 5),
        ),
        isFalse,
      );
    });
  });

  group('nothing that is not a DatabaseException is corruption', () {
    final notCorruption = <String, Object>{
      'a filesystem error': const FormatException('nope'),
      'our own migration failure': const CruxMigrationFailedException(
        storeName: 'test store',
        path: '/tmp/trends.db',
        version: 2,
        description: 'Add label',
        fromVersion: 1,
        toVersion: 2,
        cause: 'duplicate column name: label',
      ),
      'a version skew': const CruxSchemaVersionSkewException(
        storeName: 'test store',
        path: '/tmp/trends.db',
        fileVersion: 4,
        appVersion: 3,
      ),
      'a string that says the words': 'database disk image is malformed',
    };

    for (final entry in notCorruption.entries) {
      test('${entry.key} is not corruption', () {
        expect(isSqliteCorruption(entry.value), isFalse);
      });
    }
  });

  group('the four failures are distinguishable by type', () {
    const corruption = CruxDatabaseCorruptionException(
      storeName: 'test store',
      path: '/tmp/trends.db',
      recovery: CruxDbRecovery.renameAside,
      quarantinedPath: '/tmp/trends.db.corrupt-20260820T090000Z',
      cause: 'file is not a database',
    );
    const migrationFailure = CruxMigrationFailedException(
      storeName: 'test store',
      path: '/tmp/trends.db',
      version: 2,
      description: 'Add label',
      fromVersion: 1,
      toVersion: 2,
      cause: 'duplicate column name: label',
    );
    const skew = CruxSchemaVersionSkewException(
      storeName: 'test store',
      path: '/tmp/trends.db',
      fileVersion: 4,
      appVersion: 3,
    );
    const backupRefusal = CruxBackupFailedException(
      storeName: 'test store',
      path: '/tmp/trends.db',
      kind: CruxBackupFailureKind.insufficientFreeSpace,
      backupPath: null,
      fromVersion: 1,
      toVersion: 2,
      databaseBytes: 300 * 1024 * 1024,
      freeBytes: 4 * 1024 * 1024,
    );

    test('no one of them is another', () {
      final all = <CruxSqliteException>[
        corruption,
        migrationFailure,
        skew,
        backupRefusal,
      ];
      for (final failure in all) {
        final sameType = all.where((o) => o.runtimeType == failure.runtimeType);
        expect(
          sameType,
          hasLength(1),
          reason:
              'each fault is its own type, so a handler written for one '
              'cannot silently run for another',
        );
      }
    });

    test('a diagnostics surface can switch over them exhaustively', () {
      String triage(CruxSqliteException failure) => switch (failure) {
        CruxDatabaseCorruptionException() => 'the bytes are damaged',
        CruxMigrationFailedException() => 'our bug; the data is intact',
        CruxSchemaVersionSkewException() => 'a newer build wrote this file',
        CruxBackupFailedException() => 'no backup, so no migration',
      };

      expect(triage(corruption), 'the bytes are damaged');
      expect(triage(migrationFailure), 'our bug; the data is intact');
      expect(triage(skew), 'a newer build wrote this file');
      expect(triage(backupRefusal), 'no backup, so no migration');
    });

    test('all four carry the store name and an absolute path', () {
      for (final failure in <CruxSqliteException>[
        corruption,
        migrationFailure,
        skew,
        backupRefusal,
      ]) {
        expect(failure.storeName, 'test store');
        expect(failure.path, '/tmp/trends.db');
      }
    });

    test('only corruption ever names a quarantined file', () {
      expect(
        corruption.quarantinedPath,
        '/tmp/trends.db.corrupt-20260820T090000Z',
      );
    });

    test('the messages tell a reader whether their data survived', () {
      expect(migrationFailure.toString(), contains('unchanged at v1'));
      expect(skew.toString(), contains('no data has been lost'));
      expect(corruption.toString(), contains('moved aside'));
      expect(backupRefusal.toString(), contains('untouched at v1'));
    });

    test('only the backup refusal names something the user can fix', () {
      expect(backupRefusal.toString(), contains('300.0 MiB'));
      expect(backupRefusal.toString(), contains('4.0 MiB free'));
      expect(backupRefusal.toString(), contains('Free some space'));
      expect(backupRefusal.toString(), contains('did NOT run'));
    });

    test('a migration failure names its backup when it has one', () {
      const withBackup = CruxMigrationFailedException(
        storeName: 'test store',
        path: '/tmp/trends.db',
        version: 2,
        description: 'Add label',
        fromVersion: 1,
        toVersion: 2,
        cause: 'duplicate column name: label',
        backupPath: '/tmp/trends.db.pre-v1-20260820T090000Z.bak',
      );
      expect(
        withBackup.toString(),
        contains('/tmp/trends.db.pre-v1-20260820T090000Z.bak'),
      );
      expect(withBackup.toString(), contains('has not been pruned'));
      expect(
        migrationFailure.toString(),
        isNot(contains('.bak')),
        reason: 'a store with no backup must not invent one',
      );
    });

    test('a rename that failed reads differently from one that never ran', () {
      const renameFailed = CruxDatabaseCorruptionException(
        storeName: 'test store',
        path: '/tmp/trends.db',
        recovery: CruxDbRecovery.renameAside,
        quarantinedPath: null,
        cause: 'file is not a database',
      );
      const refused = CruxDatabaseCorruptionException(
        storeName: 'test store',
        path: '/tmp/trends.db',
        recovery: CruxDbRecovery.refuse,
        quarantinedPath: null,
        cause: 'file is not a database',
      );
      expect(renameFailed.toString(), contains('FAILED'));
      expect(refused.toString(), contains('has not been modified'));
      expect(renameFailed.toString(), isNot(refused.toString()));
    });
  });
}
