// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Theme pack writes must be atomic.
///
/// The user-visible failure this prevents is quiet and confusing: a
/// crash or power loss mid-write leaves a truncated JSON document,
/// `list()` silently skips anything it cannot parse, and so the user's
/// theme simply *disappears* from Settings with no error to explain it.
void main() {
  const service = ThemePackService();

  ThemePack packOf(String id) => ThemePack(
    id: id,
    displayName: 'Pack $id',
    brightness: Brightness.dark,
    tokens: const {
      'chrome': {'scaffold.background': Color(0xFF101010)},
    },
  );

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crux_theme_atomic');
  });
  tearDown(() => dir.delete(recursive: true));

  test('save leaves no temp file behind', () async {
    await service.save(packOf('alpha'), dir);
    final names = dir.listSync().map((e) => p.basename(e.path)).toList();
    expect(names, ['alpha.crux-theme.json']);
    expect(names.any((n) => n.endsWith('.tmp')), isFalse);
  });

  test('install leaves no temp file behind', () async {
    final source = File(p.join(dir.path, 'incoming.json'));
    await source.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'id': 'beta',
        'displayName': 'Beta',
        'brightness': 'light',
        'tokens': <String, Object?>{},
      }),
    );
    final destination = Directory(p.join(dir.path, 'themes'));
    await service.install(source, destination);
    final names = destination
        .listSync()
        .map((e) => p.basename(e.path))
        .toList();
    expect(names, ['beta.crux-theme.json']);
  });

  test('overwriting an existing pack never exposes a partial file', () async {
    await service.save(packOf('gamma'), dir);
    final target = service.fileFor('gamma', dir);
    final before = await target.readAsString();
    expect(before, contains('gamma'));

    // Rewrite with a much larger document. Because the write goes to a
    // temp file and is renamed into place, the destination path only
    // ever holds a complete document — a non-atomic writeAsString would
    // truncate first, exposing an empty/partial file to any concurrent
    // reader.
    final big = ThemePack(
      id: 'gamma',
      displayName: 'Gamma',
      brightness: Brightness.dark,
      tokens: {
        'chrome': {
          for (var i = 0; i < 200; i++) 'token$i': const Color(0xFF123456),
        },
      },
    );
    await service.save(big, dir);

    final after = await target.readAsString();
    expect(() => jsonDecode(after), returnsNormally);
    expect(service.loadSync(target).tokens['chrome']!.length, 200);
  });

  test('a truncated pack is skipped by list, which is exactly the '
      'disappearance atomicity prevents', () async {
    await service.save(packOf('good'), dir);
    // Simulate the torn write a non-atomic writer could leave behind.
    await File(
      p.join(dir.path, 'torn.crux-theme.json'),
    ).writeAsString('{"schemaVersion": 1, "id": "torn", "displ');

    final headers = await service.list(dir);
    expect(
      headers.map((h) => h.id),
      ['good'],
      reason: 'the torn pack vanishes silently — hence atomic writes',
    );
  });

  test('list decodes headers without building token tables', () async {
    // list() promised header-only reads and did not
    // deliver. A header carries no token map at all, so this is
    // observable through the public API.
    await service.save(packOf('delta'), dir);
    final headers = await service.list(dir);
    expect(headers.single.id, 'delta');
    expect(headers.single.displayName, 'Pack delta');
    expect(headers.single.brightness, Brightness.dark);
  });
}
