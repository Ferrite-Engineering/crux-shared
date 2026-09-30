// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_audit/crux_audit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

AuditEvent _event(String kind, {AuditSeverity severity = AuditSeverity.info}) =>
    AuditEvent(
      timestamp: DateTime.utc(2026, 8, 21, 12),
      product: 'lintcrux',
      kind: kind,
      severity: severity,
      peerId: 'peer-1',
      payload: const {'rule': 'verible/line-length'},
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('crux_audit_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String pathIn(String name) => p.join(dir.path, name);
  List<Map<String, Object?>> linesOf(String path) => File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, Object?>)
      .toList();

  group('the format is one parseable line per event', () {
    test('appends, never rewrites', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path);
      await sink.record(_event('waiver.created'));
      await sink.record(_event('waiver.deleted'));
      await sink.close();

      final lines = linesOf(path);
      expect(lines, hasLength(2));
      expect(lines.first['kind'], 'waiver.created');
      expect(lines.last['kind'], 'waiver.deleted');
    });

    test('the timestamp is first, so sort and grep work', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path);
      await sink.record(_event('waiver.created'));
      await sink.close();

      expect(File(path).readAsStringSync(), startsWith('{"ts":'));
    });

    test('a configured but unused sink creates no file', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path);
      await sink.close();
      expect(File(path).existsSync(), isFalse);
    });

    test('the parent directory is created', () async {
      final path = pathIn(p.join('nested', 'deeper', 'audit.jsonl'));
      final sink = JsonlAuditSink(path: path);
      await sink.record(_event('waiver.created'));
      await sink.close();
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('verbosity filters, and off means off', () {
    test('off writes nothing at all', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path, verbosity: AuditVerbosity.off);
      await sink.record(_event('waiver.created'));
      await sink.record(_event('x', severity: AuditSeverity.error));
      await sink.close();
      expect(File(path).existsSync(), isFalse);
    });

    test('normal drops debug and keeps the rest', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path);
      await sink.record(_event('noisy', severity: AuditSeverity.debug));
      await sink.record(_event('kept'));
      await sink.record(_event('refused', severity: AuditSeverity.warning));
      await sink.close();

      expect(
        linesOf(path).map((l) => l['kind']),
        ['kept', 'refused'],
      );
    });

    test('verbose keeps debug', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(
        path: path,
        verbosity: AuditVerbosity.verbose,
      );
      await sink.record(_event('noisy', severity: AuditSeverity.debug));
      await sink.close();
      expect(linesOf(path), hasLength(1));
    });
  });

  group('rotation belongs to the organization', () {
    // THE rotation decision. This sink does not rotate; what it owes an
    // organization that does is not to break when their logrotate runs.
    test(
      'a moved file is not written into forever — a fresh one appears',
      () async {
        final path = pathIn('audit.jsonl');
        final sink = JsonlAuditSink(path: path);
        await sink.record(_event('before.rotation'));

        // What logrotate does: rename the live file aside.
        File(path).renameSync(pathIn('audit.jsonl.1'));

        await sink.record(_event('after.rotation'));
        await sink.close();

        expect(
          File(path).existsSync(),
          isTrue,
          reason:
              'the writer must start a fresh file at the path, not keep '
              'writing into an unlinked inode nobody can read',
        );
        expect(linesOf(path).map((l) => l['kind']), ['after.rotation']);
        expect(
          linesOf(pathIn('audit.jsonl.1')).map((l) => l['kind']),
          ['before.rotation'],
          reason: 'the rotated file belongs to the shipper and is left intact',
        );
      },
    );

    test('copy-truncate keeps working', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path);
      await sink.record(_event('before'));

      File(path).copySync(pathIn('audit.jsonl.1'));
      File(path).writeAsStringSync('');

      await sink.record(_event('after'));
      await sink.close();
      expect(linesOf(path).map((l) => l['kind']), contains('after'));
    });

    test('the byte cap refuses to grow and does NOT delete anything', () async {
      // A safety valve, not a rotation policy. Deleting an audit log is not
      // this package's decision to make.
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path, maxBytes: 1);
      await sink.record(_event('first'));
      await sink.record(_event('second'));
      await sink.close();

      expect(File(path).existsSync(), isTrue);
      expect(linesOf(path), hasLength(1), reason: 'it stopped growing');
      expect(
        sink.health.writable,
        isFalse,
        reason: 'and it says so rather than dropping events silently',
      );
    });
  });

  group('a sink that cannot write degrades loudly, and never throws', () {
    // The failure decision. Crashing the product is wrong — the user
    // is debugging a waveform. Failing silently is worse — a log that quietly
    // stopped is discovered during the investigation it was meant to support.
    test('an unwritable path does not throw into the caller', () async {
      final blocked = pathIn('blocked');
      Directory(blocked).createSync();
      // A directory where the file should be: every write fails.
      final sink = JsonlAuditSink(path: blocked);

      await expectLater(sink.record(_event('waiver.created')), completes);
      await sink.close();
    });

    test('it reports itself unhealthy, with a reason and a time', () async {
      final blocked = pathIn('blocked');
      Directory(blocked).createSync();
      final sink = JsonlAuditSink(path: blocked);
      await sink.record(_event('waiver.created'));

      expect(sink.health.writable, isFalse);
      expect(sink.health.detail, isNotNull);
      expect(sink.health.since, isNotNull);
      await sink.close();
    });

    test('the failure is reported once, not once per event', () async {
      // A full disk must not produce a second log that fills what is left.
      final blocked = pathIn('blocked');
      Directory(blocked).createSync();
      final diagnostics = <String>[];
      final sink = JsonlAuditSink(
        path: blocked,
        onDiagnostic: diagnostics.add,
      );

      for (var i = 0; i < 5; i++) {
        await sink.record(_event('waiver.created'));
      }
      await sink.close();

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('crux_audit'));
    });

    test(
      'recovery is noticed — health returns when writing works again',
      () async {
        final path = pathIn('audit.jsonl');
        final sink = JsonlAuditSink(path: path, maxBytes: 1);
        await sink.record(_event('first'));
        await sink.record(_event('second'));
        expect(sink.health.writable, isFalse);

        // The administrator archived it.
        File(path).writeAsStringSync('');
        await sink.record(_event('third'));

        expect(sink.health.writable, isTrue);
        await sink.close();
      },
    );

    test('a closed sink silently ignores further events', () async {
      final path = pathIn('audit.jsonl');
      final sink = JsonlAuditSink(path: path);
      await sink.record(_event('first'));
      await sink.close();
      await expectLater(sink.record(_event('after.close')), completes);
      expect(linesOf(path), hasLength(1));
    });
  });

  group('the noop sink', () {
    test('drops everything and reports healthy', () async {
      const sink = NoopAuditSink();
      await sink.record(_event('anything'));
      expect(sink.health.writable, isTrue);
      await sink.close();
    });
  });
}
