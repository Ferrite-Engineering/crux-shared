// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// These tests exercise the ThemePackService async API end-to-end on a
// real temp directory. Mirrors the file-level ignore in the service
// itself (see theme_pack_service.dart).
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late ThemePackService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crux_theme_service_');
    service = const ThemePackService();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  ThemePack makePack({
    String id = 'pack',
    String displayName = 'Pack',
    Brightness brightness = Brightness.dark,
  }) {
    return ThemePack(
      id: id,
      displayName: displayName,
      brightness: brightness,
      tokens: const {
        'canvas': {
          'background': Color(0xFF1A1A1A),
        },
      },
    );
  }

  group('save / load round-trip', () {
    test('save writes a file named after the pack id', () async {
      final pack = makePack(id: 'wavecrux-dark');
      final file = await service.save(pack, temp);
      expect(p.basename(file.path), 'wavecrux-dark.crux-theme.json');
      expect(await file.exists(), isTrue);
    });

    test('save creates the destination directory if missing', () async {
      final nested = Directory(p.join(temp.path, 'nested', 'themes'));
      expect(await nested.exists(), isFalse);
      final file = await service.save(makePack(), nested);
      expect(await file.exists(), isTrue);
    });

    test('load returns the same pack save wrote', () async {
      final original = makePack(displayName: 'Test Pack');
      final file = await service.save(original, temp);
      final loaded = await service.load(file);
      expect(loaded.id, original.id);
      expect(loaded.displayName, original.displayName);
      expect(loaded.color('canvas', 'background'), const Color(0xFF1A1A1A));
      expect(loaded.sourceUri, file.uri);
    });

    test('loadSync is equivalent to load', () async {
      final file = await service.save(makePack(), temp);
      final loaded = service.loadSync(file);
      expect(loaded.id, 'pack');
    });

    test('save overwrites existing file with the same id', () async {
      await service.save(makePack(displayName: 'First'), temp);
      await service.save(makePack(displayName: 'Second'), temp);
      final file = service.fileFor('pack', temp);
      final loaded = await service.load(file);
      expect(loaded.displayName, 'Second');
    });
  });

  group('list', () {
    test('returns empty list for an empty directory', () async {
      final headers = await service.list(temp);
      expect(headers, isEmpty);
    });

    test('returns empty list when directory does not exist', () async {
      final missing = Directory(p.join(temp.path, 'missing'));
      final headers = await service.list(missing);
      expect(headers, isEmpty);
    });

    test('enumerates well-formed packs', () async {
      await service.save(makePack(id: 'a', displayName: 'Alpha'), temp);
      await service.save(makePack(id: 'b', displayName: 'Beta'), temp);
      final headers = await service.list(temp);
      expect(headers.length, 2);
      final ids = headers.map((h) => h.id).toSet();
      expect(ids, {'a', 'b'});
    });

    test('skips malformed packs silently', () async {
      await service.save(makePack(id: 'good'), temp);
      final bad = File(p.join(temp.path, 'broken.crux-theme.json'));
      await bad.writeAsString('not json at all');
      final headers = await service.list(temp);
      expect(headers.length, 1);
      expect(headers.single.id, 'good');
    });

    test('ignores files without the canonical extension', () async {
      await service.save(makePack(id: 'good'), temp);
      final other = File(p.join(temp.path, 'unrelated.json'));
      await other.writeAsString('{"schemaVersion":1}');
      final headers = await service.list(temp);
      expect(headers.length, 1);
    });

    test('returned headers carry the source uri', () async {
      final saved = await service.save(makePack(), temp);
      final headers = await service.list(temp);
      expect(headers.single.sourceUri, saved.uri);
    });
  });

  group('install', () {
    test('copies source into destination using id-based name', () async {
      final sourceDir = await Directory.systemTemp.createTemp(
        'crux_theme_install_',
      );
      addTearDown(() async {
        if (await sourceDir.exists()) {
          await sourceDir.delete(recursive: true);
        }
      });
      // Write a pack to an arbitrary filename in the source dir.
      final original = makePack(id: 'imported');
      final sourceFile = File(p.join(sourceDir.path, 'whatever.json'));
      await sourceFile.writeAsString(
        const ThemePackCodec().encode(original),
      );

      final installed = await service.install(sourceFile, temp);
      expect(installed.id, 'imported');
      final destFile = service.fileFor('imported', temp);
      expect(await destFile.exists(), isTrue);
      expect(installed.sourceUri, destFile.uri);
    });

    test('throws FormatException on malformed source', () async {
      final bad = File(p.join(temp.path, 'bad.json'));
      await bad.writeAsString('not a pack');
      expect(
        () => service.install(bad, temp),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('uninstall', () {
    test('removes existing file and returns true', () async {
      await service.save(makePack(), temp);
      expect(await service.uninstall('pack', temp), isTrue);
      final file = service.fileFor('pack', temp);
      expect(await file.exists(), isFalse);
    });

    test('returns false when file does not exist', () async {
      expect(await service.uninstall('ghost', temp), isFalse);
    });
  });

  group('validate', () {
    test('returns ok for a valid pack', () async {
      final file = await service.save(makePack(), temp);
      final result = await service.validate(file);
      expect(result.isValid, isTrue);
      expect(result.pack?.id, 'pack');
    });

    test('returns failed for a malformed pack', () async {
      final bad = File(p.join(temp.path, 'bad.crux-theme.json'));
      await bad.writeAsString('not json');
      final result = await service.validate(bad);
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('returns failed for a missing file', () async {
      final missing = File(p.join(temp.path, 'missing.crux-theme.json'));
      final result = await service.validate(missing);
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });
  });

  group('fileFor', () {
    test('produces the canonical destination path', () {
      final file = service.fileFor('foo', temp);
      expect(p.basename(file.path), 'foo.crux-theme.json');
      expect(p.dirname(file.path), temp.path);
    });
  });

  group('themePackExtension', () {
    test('is .crux-theme.json', () {
      expect(ThemePackService.themePackExtension, '.crux-theme.json');
    });
  });
}
