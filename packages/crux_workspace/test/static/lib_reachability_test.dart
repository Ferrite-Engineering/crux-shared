// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: every `lib/**.dart` file in every package is reachable from
// that package's entry points, or is listed below with the reason it is not.
//
// THE DEFECT CLASS. A file under `lib/src/` that nothing imports compiles,
// analyzes clean, keeps its tests green and ships in nobody's build. It still
// costs what live code costs: it is read, grepped, updated in sweeps and
// trusted by the next person who finds it, and its doc comments describe a
// mechanism no product runs. Code-level dead ends have already been found in
// this repository by hand — providers nothing watched, one documented as the
// gate while the real gate was a sibling — and a file is the coarsest version
// of the same defect. This makes the machine look for it.
//
// ENTRY POINTS. A package's public surface is its top-level `lib/*.dart`
// libraries (the barrels; each has an API golden under `api/`) plus anything
// under `bin/` (the `crux-policy` CLI). Nothing else in `lib/` is meant to be
// imported from outside, so a file those cannot reach is reachable by no
// consumer that respects the `src/` convention.
//
// EDGES. `import`, `export` and `part` directives, read from the parsed AST,
// followed wherever they point inside the same package — `lib/`, `bin/`, or a
// file such as `tool/policy_signer.dart` that a `bin/` entry imports. Every
// target of a conditional directive (`if (dart.library.io) '…'`) is an edge:
// each is the file some platform compiles. `part of` is not an edge — a part
// is reachable only through its library's `part` directive, so a part file
// whose library dropped it is dead however it names its parent. Other
// packages' `package:` URIs and `dart:` libraries end the walk.
//
// WHAT THIS DOES NOT CATCH. A reachable file whose public symbols no consumer
// uses; that needs the consumers, which this repository's CI does not check
// out, and is `tool/unused-exports.py`'s question instead. A file reachable
// only from `test/` counts as unreachable here, deliberately: tests are not
// consumers.
//
// The walker's own behaviour — orphan found, conditional targets followed, a
// `part` followed and a `part of` not — is pinned against a synthetic package
// by the last group below, so the guard cannot silently turn into one that
// reaches everything.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `lib/` files allowed to be unreachable, keyed by workspace-relative path,
/// each with the reason.
///
/// Empty, and worth keeping empty. The bar for an entry is a file that must
/// exist under `lib/` and must not be imported by anything in its package — a
/// file loaded by path at run time, say. "Something might use it later" is not
/// a reason; delete the file and let git remember it.
///
/// When a listed file becomes reachable or is deleted, the second test fails
/// until its entry goes, so this cannot rot into a list of files that are
/// fine.
const Map<String, String> _allowedUnreachable = <String, String>{};

void main() {
  final root = _workspaceRoot();
  final packageDirs = Directory(p.join(root, 'packages')).listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  final packages = <PackageReach>[
    for (final dir in packageDirs)
      if (dir is Directory && Directory(p.join(dir.path, 'lib')).existsSync())
        walkPackage(dir.path),
  ];

  String rel(String path) => p.relative(path, from: root);
  String offence(PackageReach pkg, String file) =>
      "${rel(file)}: not reachable from ${pkg.name}'s entry points "
      '(${pkg.entryPoints.map(rel).join(', ')})';

  test('the workspace layout resolved, and the walk is not vacuous', () {
    expect(packages.length, greaterThan(30), reason: 'packages not found');
    for (final pkg in packages) {
      expect(
        pkg.entryPoints,
        isNotEmpty,
        reason: '${pkg.name} has a lib/ and no top-level lib/*.dart barrel',
      );
    }
    final files = packages.fold<int>(0, (n, pkg) => n + pkg.libFiles.length);
    final reached = packages.fold<int>(
      0,
      (n, pkg) => n + pkg.libFiles.intersection(pkg.reached).length,
    );
    expect(files, greaterThan(300), reason: 'lib files not found');
    // If directive resolution broke, almost nothing past the barrels would be
    // reached and the failure below would drown in noise. Say so directly.
    expect(
      reached,
      greaterThan(files * 9 ~/ 10),
      reason: 'the walker reached $reached of $files lib files',
    );
  });

  test('every lib file is reachable from its package entry points, or is '
      'allowlisted with the reason', () {
    final offenders = <String>[
      for (final pkg in packages)
        for (final file in pkg.unreachable)
          if (!_allowedUnreachable.containsKey(rel(file))) offence(pkg, file),
    ]..sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'A file under lib/ is imported, exported or parted by nothing its '
          'package exposes, so no build contains it. Delete it; or, if a '
          'barrel should expose it, add the export (and regenerate the API '
          'golden); or, if it genuinely must stay unreachable, add it to '
          '_allowedUnreachable with the reason.\n${offenders.join('\n')}',
    );
  });

  test('every allowlist entry is still a file, and still unreachable', () {
    final unreachable = {
      for (final pkg in packages) ...pkg.unreachable.map(rel),
    };
    final stale = [
      for (final path in _allowedUnreachable.keys)
        if (!unreachable.contains(path)) path,
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'These allowances outlived the problem — the file was deleted or '
          'became reachable. Delete the entries.\n${stale.join('\n')}',
    );
  });

  test('every directive in a reachable file resolves to a file', () {
    // Proves the walker's URI resolution rather than the code's: the analyzer
    // already refuses a missing import, so a finding here means this guard
    // mis-resolved a path and its verdicts above cannot be trusted.
    final dangling = [
      for (final pkg in packages) ...pkg.dangling.map((d) => '${pkg.name}: $d'),
    ];
    expect(dangling, isEmpty, reason: dangling.join('\n'));
  });

  group('the walker, on a synthetic package', () {
    late Directory fixture;
    late PackageReach reach;

    setUpAll(() {
      fixture = Directory.systemTemp.createTempSync('crux_reach_');
      void write(String path, String body) {
        File(p.join(fixture.path, path))
          ..createSync(recursive: true)
          ..writeAsStringSync(body);
      }

      write('pubspec.yaml', 'name: fixture_pkg\n');
      write('lib/fixture_pkg.dart', '''
library;

export 'package:fixture_pkg/src/a.dart';
export 'src/host.dart';
// export 'src/commented_out.dart';
''');
      write('lib/src/a.dart', '''
import 'dart:io';

import 'package:other_pkg/other.dart';

import 'b.dart';

part 'a_part.dart';
''');
      write('lib/src/a_part.dart', "part of 'a.dart';\n");
      write('lib/src/b.dart', '');
      write(
        'lib/src/host.dart',
        "export 'host_stub.dart' if (dart.library.io) 'host_io.dart';\n",
      );
      write('lib/src/host_stub.dart', '');
      write('lib/src/host_io.dart', '');
      write('lib/src/commented_out.dart', '');
      write('lib/src/orphan.dart', "import 'b.dart';\n");
      write('lib/src/stray_part.dart', "part of 'a.dart';\n");
      write('bin/tool.dart', "import '../tool/helper.dart';\n");
      write('tool/helper.dart', "import 'package:fixture_pkg/src/cli.dart';\n");
      write('lib/src/cli.dart', '');
      reach = walkPackage(fixture.path);
    });

    tearDownAll(() => fixture.deleteSync(recursive: true));

    Set<String> names(Iterable<String> files) => {
      for (final f in files)
        if (p.isWithin(p.join(fixture.path, 'lib'), f))
          p.relative(f, from: p.join(fixture.path, 'lib')),
    };

    test('an orphan, a stray part and a commented-out export are unreachable '
        '— and nothing else is', () {
      expect(names(reach.unreachable), {
        'src/orphan.dart',
        'src/stray_part.dart',
        'src/commented_out.dart',
      });
    });

    test('both targets of a conditional export are reached', () {
      expect(
        names(reach.reached),
        containsAll(<String>['src/host_stub.dart', 'src/host_io.dart']),
      );
    });

    test('a part is reached through its part directive', () {
      expect(names(reach.reached), contains('src/a_part.dart'));
    });

    test('bin/ is an entry point, and its edges leave lib/ and come back', () {
      expect(names(reach.reached), contains('src/cli.dart'));
    });

    test('another package and dart: end the walk without a dangling edge', () {
      expect(reach.dangling, isEmpty);
    });
  });
}

/// One package's reachability walk.
class PackageReach {
  PackageReach({
    required this.name,
    required this.entryPoints,
    required this.libFiles,
    required this.reached,
    required this.dangling,
  });

  /// The `name:` from the package's pubspec.
  final String name;

  /// Absolute paths of the files the walk started from.
  final List<String> entryPoints;

  /// Absolute paths of every `lib/**.dart` file.
  final Set<String> libFiles;

  /// Absolute paths of every file the walk reached, in or out of `lib/`.
  final Set<String> reached;

  /// `from → uri` for each directive whose in-package target does not exist.
  final List<String> dangling;

  /// The `lib/` files nothing reached.
  Set<String> get unreachable => libFiles.difference(reached);
}

/// Walks the package at [packageRoot] from its entry points.
PackageReach walkPackage(String packageRoot) {
  final root = p.normalize(p.absolute(packageRoot));
  final name = RegExp(r'^name:\s*(\S+)', multiLine: true)
      .firstMatch(File(p.join(root, 'pubspec.yaml')).readAsStringSync())!
      .group(1)!;
  final lib = p.join(root, 'lib');

  List<String> dartFilesIn(String dir, {required bool recursive}) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return [
      for (final f in d.listSync(recursive: recursive))
        if (f is File && f.path.endsWith('.dart')) p.normalize(f.path),
    ]..sort();
  }

  final entryPoints = [
    ...dartFilesIn(lib, recursive: false),
    ...dartFilesIn(p.join(root, 'bin'), recursive: true),
  ];
  final reached = <String>{};
  final dangling = <String>[];
  final queue = [...entryPoints];

  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    if (!reached.add(file)) continue;
    for (final uri in _directiveUris(File(file).readAsStringSync())) {
      final String target;
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:')) {
        final rest = uri.substring('package:'.length);
        final slash = rest.indexOf('/');
        if (slash < 0 || rest.substring(0, slash) != name) continue;
        target = p.normalize(p.join(lib, rest.substring(slash + 1)));
      } else {
        target = p.normalize(p.join(p.dirname(file), uri));
      }
      // Never walk out of the package, whatever a relative URI says.
      if (!p.isWithin(root, target)) continue;
      if (!File(target).existsSync()) {
        dangling.add('${p.relative(file, from: root)} → $uri');
        continue;
      }
      if (!reached.contains(target)) queue.add(target);
    }
  }

  return PackageReach(
    name: name,
    entryPoints: entryPoints,
    libFiles: dartFilesIn(lib, recursive: true).toSet(),
    reached: reached,
    dangling: dangling,
  );
}

/// Every URI an `import`, `export` or `part` directive in [source] names,
/// including each conditional alternative. `part of` names no edge.
List<String> _directiveUris(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  return [
    for (final directive in unit.directives)
      if (directive is NamespaceDirective) ...[
        ?directive.uri.stringValue,
        for (final configuration in directive.configurations)
          ?configuration.uri.stringValue,
      ] else if (directive is PartDirective)
        ?directive.uri.stringValue,
  ];
}

/// The crux-shared workspace root, found by walking up from the test's working
/// directory until the root `pubspec.yaml` naming the melos workspace is found.
String _workspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: crux_shared_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate the crux-shared workspace root from '
    '${Directory.current.path}',
  );
}
