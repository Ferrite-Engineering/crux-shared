// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('crux_io_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File dest([String name = 'doc.json']) => File('${dir.path}/$name');

  group('writeStringAtomic', () {
    test('creates the file with the supplied contents', () async {
      await writeStringAtomic(dest(), 'hello');
      expect(dest().readAsStringSync(), 'hello');
    });

    test('replaces existing contents', () async {
      dest().writeAsStringSync('old');
      await writeStringAtomic(dest(), 'new');
      expect(dest().readAsStringSync(), 'new');
    });

    test('creates missing parent directories', () async {
      final nested = File('${dir.path}/a/b/c/doc.json');
      await writeStringAtomic(nested, 'deep');
      expect(nested.readAsStringSync(), 'deep');
    });

    test('leaves no scratch file behind on success', () async {
      await writeStringAtomic(dest(), 'hello');
      expect(_tempFilesIn(dir), isEmpty);
    });

    test(
      'a crash before the rename leaves the previous document intact',
      () async {
        dest().writeAsStringSync('original');
        await expectLater(
          writeStringAtomic(
            dest(),
            'replacement',
            onBeforeRename: () => throw const FileSystemException('boom'),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(dest().readAsStringSync(), 'original');
      },
    );

    test('cleans up the scratch file when the write fails', () async {
      await expectLater(
        writeStringAtomic(
          dest(),
          'replacement',
          onBeforeRename: () => throw const FileSystemException('boom'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(_tempFilesIn(dir), isEmpty);
    });

    test('rethrows rather than swallowing the failure', () async {
      await expectLater(
        writeStringAtomic(
          dest(),
          'x',
          onBeforeRename: () => throw StateError('nope'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('two overlapping writes use distinct scratch files', () async {
      // A shared `<dest>.tmp` would let the second writer consume the first
      // writer's scratch file; the loser's rename then fails with ENOENT and
      // its save is silently lost. Both must land, last-writer-wins.
      await Future.wait<void>([
        writeStringAtomic(dest(), 'first'),
        writeStringAtomic(dest(), 'second'),
      ]);
      expect(dest().readAsStringSync(), anyOf('first', 'second'));
      expect(_tempFilesIn(dir), isEmpty);
    });

    test('scratch names are unique across sequential writes', () async {
      final names = <String>{};
      for (var i = 0; i < 25; i++) {
        await writeStringAtomic(
          dest(),
          'v$i',
          onBeforeRename: () {
            names.addAll(_tempFilesIn(dir).map((f) => f.path));
          },
        );
      }
      expect(names, hasLength(25));
    });

    test('both durability levels produce the same bytes', () async {
      await writeStringAtomic(
        dest('a'),
        'payload',
        durability: WriteDurability.ephemeral,
      );
      await writeStringAtomic(dest('b'), 'payload');
      expect(dest('a').readAsStringSync(), dest('b').readAsStringSync());
    });
  });

  group('WriteDurability', () {
    test('durable flushes and is the default', () {
      expect(WriteDurability.durable.flush, isTrue);
    });

    test('ephemeral does not flush', () {
      expect(WriteDurability.ephemeral.flush, isFalse);
    });
  });

  group('writeJsonAtomic', () {
    test('writes a pretty-printed, re-readable document', () async {
      await writeJsonAtomic(dest(), {
        'version': 1,
        'items': ['a', 'b'],
      });
      final raw = dest().readAsStringSync();
      expect(raw, contains('\n  '));
      expect(jsonDecode(raw), {
        'version': 1,
        'items': ['a', 'b'],
      });
    });

    test('honours the crash seam like writeStringAtomic', () async {
      await writeJsonAtomic(dest(), {'v': 1});
      await expectLater(
        writeJsonAtomic(
          dest(),
          {'v': 2},
          onBeforeRename: () => throw const FileSystemException('boom'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(dest().readAsStringSync()), {'v': 1});
    });

    test('an unencodable payload leaves the destination untouched', () async {
      dest().writeAsStringSync('{"v":1}');
      await expectLater(
        writeJsonAtomic(dest(), Object()),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(dest().readAsStringSync(), '{"v":1}');
      expect(_tempFilesIn(dir), isEmpty);
    });
  });
}

List<File> _tempFilesIn(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.tmp'))
    .toList();
