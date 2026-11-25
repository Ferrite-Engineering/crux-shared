// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The path functions that resolve a relative path against the working
/// directory.
///
/// The working directory belongs to the process, and `dart test` runs the test
/// files of a package concurrently in one process. A test that changes it
/// changes it for every other file: one file captured another's temp dir as
/// the directory to restore, and a child process another file started while it
/// was changed found its working directory deleted under it. These tests
/// therefore never change it. They answer `Directory.current` from the zone
/// they run in, which is what the functions under test read.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_io_cwd_');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// Runs [body] with [temp] as the working directory of this zone only.
  T inTemp<T>(T Function() body) =>
      IOOverrides.runZoned(body, getCurrentDirectory: () => temp);

  /// The temp dir itself sits under a symlink on macOS (`/var` →
  /// `/private/var`), so tests that need a stable absolute path compare
  /// against the resolved form rather than the string `createTempSync`
  /// returned.
  String resolved(String path) => canonicalizePath(path);

  test('isPathWithin: a relative root is made absolute against the working '
      'directory', () {
    final root = p.join(temp.path, 'project');
    Directory(p.join(root, 'runs', 'r1')).createSync(recursive: true);
    expect(
      inTemp(() => isPathWithin('project', p.join(root, 'runs'))),
      isTrue,
    );
  });

  test('canonicalizePath makes a relative path absolute', () {
    final file = File(p.join(temp.path, 'design.vcd'))..writeAsStringSync('x');

    expect(inTemp(() => canonicalizePath('design.vcd')), resolved(file.path));
    expect(inTemp(() => canonicalizePath('./design.vcd')), resolved(file.path));
  });

  test('isSamePath matches across relative, dot-segment and trailing-slash '
      'forms', () {
    final file = File(p.join(temp.path, 'sub', 'design.vcd'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');

    expect(
      inTemp(() => isSamePath(file.path, p.join('sub', 'design.vcd'))),
      isTrue,
    );
    expect(
      isSamePath(file.path, p.join(temp.path, 'sub', '.', 'design.vcd')),
      isTrue,
    );
  });
}
