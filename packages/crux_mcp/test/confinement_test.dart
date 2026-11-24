// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late String root;
  late String outside;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('crux_mcp_confine_');
    root = p.join(sandbox.path, 'root');
    outside = p.join(sandbox.path, 'outside');
    Directory(p.join(root, 'rtl')).createSync(recursive: true);
    Directory(outside).createSync();
    File(p.join(root, 'rtl', 'a.sv')).writeAsStringSync('');
    File(p.join(outside, 'secret.sv')).writeAsStringSync('');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  String? admitted(ConfinementResult r) => switch (r) {
    ConfinedPath(:final path) => path,
    RefusedPath() => null,
  };

  test('a path inside the root is admitted as the absolute text checked', () {
    final c = Confinement(root);
    expect(c.rootProblem(), isNull);
    expect(admitted(c.confine('rtl/a.sv')), p.join(root, 'rtl', 'a.sv'));
    final absolute = p.join(root, 'rtl', 'a.sv');
    expect(admitted(c.confine(absolute)), absolute);
    expect(admitted(c.confine('.')), p.join(root, '.'));
  });

  test('a path that does not exist yet resolves through its ancestor', () {
    final c = Confinement(root);
    expect(admitted(c.confine('rtl/new/b.sv')), isNotNull);
    expect(admitted(c.confine('fresh.vcd')), isNotNull);
  });

  test('a path outside the root is refused and named', () {
    final c = Confinement(root);
    final r = c.confine(p.join(outside, 'secret.sv'));
    expect(r, isA<RefusedPath>());
    expect((r as RefusedPath).message, contains('outside the root'));
    expect(r.given, p.join(outside, 'secret.sv'));
    expect(c.confine('../outside/secret.sv'), isA<RefusedPath>());
    expect(c.confine('rtl/../../outside/secret.sv'), isA<RefusedPath>());
  });

  test('a `..` below a name that does not exist is refused', () {
    final r = Confinement(root).confine('missing/../rtl/a.sv');
    expect(r, isA<RefusedPath>());
    expect((r as RefusedPath).message, contains('cannot be resolved'));
  });

  test('a symbolic link out of the root is refused', () {
    if (Platform.isWindows) return;
    Link(p.join(root, 'escape')).createSync(outside);
    Link(p.join(root, 'rtl', 'b.sv')).createSync(
      p.join(outside, 'secret.sv'),
    );
    final c = Confinement(root);
    expect(c.confine('escape/secret.sv'), isA<RefusedPath>());
    expect(c.confine('rtl/b.sv'), isA<RefusedPath>());
    expect(c.confine('escape/new.sv'), isA<RefusedPath>());
  });

  test('network and device spellings are refused on their text', () {
    final c = Confinement(root);
    for (final spelling in <String>[
      r'\\server\share\x.sv',
      r'\\?\C:\x.sv',
      r'\\.\pipe\x',
      '//server/share/x.sv',
    ]) {
      final r = c.confine(spelling);
      expect(r, isA<RefusedPath>(), reason: spelling);
      expect((r as RefusedPath).message, contains('network or device'));
    }
  });

  test('empty, NUL and padded paths are refused', () {
    final c = Confinement(root);
    expect(c.confine(''), isA<RefusedPath>());
    expect(c.confine('a\x00b'), isA<RefusedPath>());
    expect(c.confine('rtl/a.sv '), isA<RefusedPath>());
  });

  test('confineAll checks every named file against a base', () {
    final c = Confinement(root);
    expect(c.confineAll(<String>['rtl/a.sv', 'rtl/new.sv']), isNull);
    expect(c.confineAll(<String>['a.sv'], base: p.join(root, 'rtl')), isNull);
    final r = c.confineAll(<String>[
      'rtl/a.sv',
      '../outside/secret.sv',
      'rtl/b.sv',
    ]);
    expect(r?.given, '../outside/secret.sv');
    expect(
      c.confineAll(<String>[
        '../../outside/secret.sv',
      ], base: p.join(root, 'rtl')),
      isNotNull,
    );
  });

  test('a root that is not a directory is said', () {
    expect(Confinement(p.join(root, 'rtl', 'a.sv')).rootProblem(), isNotNull);
    expect(Confinement(p.join(root, 'none')).rootProblem(), isNotNull);
  });

  test('a refusal reason other than the two named is passed on', () {
    final c = Confinement.withRule(root, (_, _) => 'file_path is odd');
    final r = c.confine('x');
    expect((r as RefusedPath).message, '`x` is refused: the path is odd');
  });
}
