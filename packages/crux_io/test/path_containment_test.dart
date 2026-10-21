// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_io/src/path_identity_host_stub.dart' as web_host;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String root;
  late String outside;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_io_containment_');
    root = p.join(temp.path, 'project');
    outside = p.join(temp.path, 'elsewhere');
    Directory(p.join(root, 'runs', 'r1')).createSync(recursive: true);
    Directory(outside).createSync();
    File(p.join(outside, 'secret.txt')).writeAsStringSync('x');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('isPathWithin', () {
    test('the root itself and anything below it are inside', () {
      expect(isPathWithin(root, root), isTrue);
      expect(isPathWithin(root, p.join(root, 'runs', 'r1')), isTrue);
      expect(isPathWithin(root, p.join(root, 'runs', 'not-yet')), isTrue);
    });

    test('a sibling with the root as a name prefix is outside', () {
      final sibling = '$root-old';
      Directory(sibling).createSync();
      expect(isPathWithin(root, sibling), isFalse);
    });

    test('a path that climbs out with .. is outside', () {
      expect(
        isPathWithin(root, p.join(root, 'runs', '..', '..', 'elsewhere')),
        isFalse,
      );
    });

    test('a .. below a directory that does not exist has no key', () {
      expect(isPathWithin(root, p.join(root, 'ghost', '..', 'runs')), isFalse);
    });

    test('a link inside the root that points out is outside', () {
      final link = p.join(root, 'runs', 'escape');
      Link(link).createSync(outside);
      expect(isPathWithin(root, link), isFalse);
      expect(isPathWithin(root, p.join(link, 'secret.txt')), isFalse);
    });

    test('link/.. is judged where the filesystem lands, not as text', () {
      // `<root>/escape/..` as text is `<root>`; the filesystem follows the
      // link first and lands beside its target, outside the root.
      Link(p.join(root, 'up')).createSync(outside);
      expect(isPathWithin(root, p.join(root, 'up', '..', 'project')), isTrue);
      expect(isPathWithin(root, p.join(root, 'up', '..')), isFalse);
    });

    test('a root spelled through a link contains paths spelled through '
        'its target', () {
      final alias = p.join(temp.path, 'alias');
      Link(alias).createSync(root);
      expect(isPathWithin(alias, p.join(root, 'runs')), isTrue);
      expect(isPathWithin(root, p.join(alias, 'runs')), isTrue);
    });

    test('a dangling link has no key', () {
      final dangling = p.join(root, 'dangling');
      Link(dangling).createSync(p.join(temp.path, 'nothing-here'));
      expect(isPathWithin(root, p.join(dangling, 'x')), isFalse);
    });

    test('relative, blank-padded, empty and NUL paths are never inside', () {
      for (final path in <String>[
        'runs/r1',
        ' ${p.join(root, 'runs')}',
        '${p.join(root, 'runs')} ',
        '',
        '${p.join(root, 'runs')}\x00',
      ]) {
        expect(isPathWithin(root, path), isFalse, reason: '"$path"');
      }
    });

    test('a relative root is made absolute against the working directory', () {
      final previous = Directory.current;
      Directory.current = temp;
      addTearDown(() => Directory.current = previous);
      expect(isPathWithin('project', p.join(root, 'runs')), isTrue);
    });

    test('a blank root contains nothing', () {
      expect(isPathWithin('  ', p.join(root, 'runs')), isFalse);
    });
  });

  group('containingRoot', () {
    test('returns the root as given, the first that contains the path', () {
      expect(
        containingRoot(p.join(root, 'runs'), <String>['', outside, root]),
        root,
      );
    });

    test('null when no root contains the path', () {
      expect(
        containingRoot(p.join(outside, 'secret.txt'), <String>[root]),
        isNull,
      );
      expect(containingRoot(p.join(root, 'runs'), const <String>[]), isNull);
    });
  });

  group('containmentKey', () {
    test('an existing path keys to its resolved form', () {
      final key = containmentKey(p.join(root, 'runs'));
      final expected = p.join(
        Directory(root).resolveSymbolicLinksSync(),
        'runs',
      );
      expect(
        key,
        filesystemIsCaseInsensitive ? expected.toLowerCase() : expected,
      );
    });

    test('empty and NUL-holding paths have no key', () {
      expect(containmentKey(''), isNull);
      expect(containmentKey('/a\x00b'), isNull);
    });

    test('in a browser: the location itself, none with a .. segment', () {
      expect(web_host.hostContainmentKey('/runs/r1'), '/runs/r1');
      expect(web_host.hostContainmentKey('/runs/../etc'), isNull);
    });
  });
}
