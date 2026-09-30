// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_io/src/path_identity_host_stub.dart' as web_host;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crux_io_path_identity_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// The temp dir itself sits under a symlink on macOS (`/var` →
  /// `/private/var`), so tests that need a stable absolute path compare
  /// against the resolved form rather than the string `createTempSync`
  /// returned.
  String resolved(String path) => canonicalizePath(path);

  group('canonicalizePath', () {
    test('returns the empty string for an empty or blank path', () {
      expect(canonicalizePath(''), isEmpty);
      expect(canonicalizePath('   '), isEmpty);
    });

    test('makes a relative path absolute', () {
      final file = File(p.join(tempDir.path, 'design.vcd'))
        ..writeAsStringSync('x');
      final previous = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = previous);

      expect(canonicalizePath('design.vcd'), resolved(file.path));
      expect(canonicalizePath('./design.vcd'), resolved(file.path));
    });

    test('collapses . and .. segments', () {
      final file = File(p.join(tempDir.path, 'nested', 'design.vcd'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('x');

      final indirect = p.join(
        tempDir.path,
        'nested',
        '..',
        'nested',
        'design.vcd',
      );
      expect(canonicalizePath(indirect), resolved(file.path));
    });

    test('drops a trailing separator', () {
      final dir = Directory(p.join(tempDir.path, 'project'))..createSync();
      expect(
        canonicalizePath('${dir.path}${p.separator}'),
        canonicalizePath(dir.path),
      );
    });

    test('resolves a symlink to its target', () {
      final target = File(p.join(tempDir.path, 'real.vcd'))
        ..writeAsStringSync('x');
      final link = Link(p.join(tempDir.path, 'alias.vcd'))
        ..createSync(target.path);

      expect(canonicalizePath(link.path), canonicalizePath(target.path));
    });

    test('leaves symlinks alone when resolution is switched off', () {
      final target = File(p.join(tempDir.path, 'real.vcd'))
        ..writeAsStringSync('x');
      Link(p.join(tempDir.path, 'alias.vcd')).createSync(target.path);

      final aliasPath = p.join(tempDir.path, 'alias.vcd');
      expect(
        canonicalizePath(aliasPath, resolveSymlinks: false),
        p.normalize(p.absolute(aliasPath)),
      );
    });

    test('fails soft on a path that does not exist', () {
      // A workspace document routinely outlives the file it points at; a
      // path that cannot be resolved must still normalize, not throw.
      final ghost = p.join(tempDir.path, 'gone', '..', 'gone', 'x.vcd');
      expect(
        canonicalizePath(ghost),
        p.normalize(p.absolute(ghost)),
      );
    });

    test('is idempotent', () {
      final file = File(p.join(tempDir.path, 'design.vcd'))
        ..writeAsStringSync('x');
      final once = canonicalizePath(file.path);
      expect(canonicalizePath(once), once);
    });
  });

  group('canonicalPathKey', () {
    test('folds case when the filesystem ignores case', () {
      expect(
        canonicalPathKey('/Projects/Foo.vcd', caseInsensitive: true),
        canonicalPathKey('/projects/foo.vcd', caseInsensitive: true),
      );
    });

    test('keeps case distinct on a case-sensitive filesystem', () {
      expect(
        canonicalPathKey('/projects/Foo.vcd', caseInsensitive: false),
        isNot(canonicalPathKey('/projects/foo.vcd', caseInsensitive: false)),
      );
    });

    test('defaults to the platform filesystem convention', () {
      final key = canonicalPathKey('/Projects/Foo.vcd');
      expect(
        key,
        filesystemIsCaseInsensitive
            ? canonicalPathKey('/projects/foo.vcd')
            : canonicalizePath('/Projects/Foo.vcd'),
      );
    });

    test('returns the empty string for an empty path', () {
      expect(canonicalPathKey(''), isEmpty);
    });
  });

  group('isSamePath', () {
    test('matches across relative, dot-segment and trailing-slash forms', () {
      final file = File(p.join(tempDir.path, 'sub', 'design.vcd'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('x');

      final previous = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = previous);

      expect(isSamePath(file.path, p.join('sub', 'design.vcd')), isTrue);
      expect(
        isSamePath(file.path, p.join(tempDir.path, 'sub', '.', 'design.vcd')),
        isTrue,
      );
    });

    test('matches across a symlink', () {
      final target = File(p.join(tempDir.path, 'real.vcd'))
        ..writeAsStringSync('x');
      final link = Link(p.join(tempDir.path, 'alias.vcd'))
        ..createSync(target.path);

      expect(isSamePath(link.path, target.path), isTrue);
    });

    test('two absent paths are not the same file', () {
      // An unset path is unknown, not a shared identity — otherwise every
      // unsaved document in an app collapses into one.
      expect(isSamePath('', ''), isFalse);
      expect(isSamePath('   ', ''), isFalse);
    });

    test('distinct files do not match', () {
      expect(
        isSamePath(
          p.join(tempDir.path, 'a.vcd'),
          p.join(tempDir.path, 'b.vcd'),
        ),
        isFalse,
      );
    });
  });

  group('the host a browser gets', () {
    // The conditional export picks this stub wherever `dart:io` is missing.
    // `test/web/path_identity_web_test.dart` runs the public functions through
    // it in Chrome; this pins the stub's own answers on the VM, where it is
    // otherwise never loaded.
    test('treats a location as already canonical', () {
      final real = p.join(tempDir.path, 'sub', '..', 'design.vcd');
      File(p.join(tempDir.path, 'design.vcd')).writeAsStringSync('');

      expect(
        web_host.hostCanonicalizePath(real, resolveSymlinks: true),
        real,
        reason: 'no working directory, no normalisation, no symlink lookup',
      );
    });

    test('reports no case-folding filesystem', () {
      expect(web_host.hostFilesystemIsCaseInsensitive(), isFalse);
    });
  });
}
