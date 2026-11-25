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
/// files of a package concurrently in one process. A file that changes it
/// while another does captures the other's directory as "previous" and puts it
/// back after it is deleted. These tests are therefore the only ones in this
/// package that change it, and they are in one file, whose tests run one at a
/// time.
void main() {
  late Directory temp;
  late Directory previous;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_io_cwd_');
    previous = Directory.current;
    Directory.current = temp;
  });

  tearDown(() {
    Directory.current = previous;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// The temp dir itself sits under a symlink on macOS (`/var` →
  /// `/private/var`), so tests that need a stable absolute path compare
  /// against the resolved form rather than the string `createTempSync`
  /// returned.
  String resolved(String path) => canonicalizePath(path);

  test('isPathWithin: a relative root is made absolute against the working '
      'directory', () {
    final root = p.join(temp.path, 'project');
    Directory(p.join(root, 'runs', 'r1')).createSync(recursive: true);
    expect(isPathWithin('project', p.join(root, 'runs')), isTrue);
  });

  test('canonicalizePath makes a relative path absolute', () {
    final file = File(p.join(temp.path, 'design.vcd'))..writeAsStringSync('x');

    expect(canonicalizePath('design.vcd'), resolved(file.path));
    expect(canonicalizePath('./design.vcd'), resolved(file.path));
  });

  test('isSamePath matches across relative, dot-segment and trailing-slash '
      'forms', () {
    final file = File(p.join(temp.path, 'sub', 'design.vcd'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');

    expect(isSamePath(file.path, p.join('sub', 'design.vcd')), isTrue);
    expect(
      isSamePath(file.path, p.join(temp.path, 'sub', '.', 'design.vcd')),
      isTrue,
    );
  });
}
