// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `crux_policy` is pure Dart, permanently.
///
/// The reason is the headless binaries. The `lintcrux` Pro CLI reads this file
/// for its gate threshold, and the `crux-policy` CLI is nothing but this
/// package with a command line on it. Both are built with `dart build cli`. A
/// Flutter
/// import anywhere in the transitive graph drags `dart:ui` into the AOT kernel
/// and kills that compile — not with a comprehensible error, but with an opaque
/// FFI-transformer crash. It has already happened once in this codebase:
/// `crux_license` had to grow an entire second `crux_license_core` barrel after
/// its main barrel did exactly that.
///
/// Nothing in a JSON parser, a signature check or a precedence table wants
/// Flutter. Reaching for it is the signal that the wrong thing is being built
/// here — the Settings-side "show this as locked" UI belongs per product, or in
/// a separate `crux_policy_ui` if it ever wants sharing.
///
/// The coupling is cheap to acquire by accident — one import during a refactor,
/// one dependency added to the pubspec, one sibling package that itself grows a
/// Flutter dependency — and expensive to shed afterwards. This guard makes it
/// impossible to acquire silently, which is the only reason the promise in the
/// package's docs is worth anything.
void main() {
  // `dart test` runs with the package root as cwd.
  final packageRoot = Directory.current;

  group('crux_policy stays pure Dart', () {
    test('the pubspec declares no Flutter dependency', () {
      final pubspec = File(p.join(packageRoot.path, 'pubspec.yaml'));
      expect(
        pubspec.existsSync(),
        isTrue,
        reason: 'the guard must run against the real pubspec, not a stub',
      );
      expect(
        RegExp(
          r'^\s{2}flutter\s*:',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync()),
        isFalse,
        reason:
            'a `flutter:` dependency here breaks `dart build cli` in both '
            'product CLIs and in the crux-policy CLI',
      );
    });

    test('no source imports or exports Flutter', () {
      final offenders = <String>[];
      for (final dir in ['lib', 'test']) {
        final root = Directory(p.join(packageRoot.path, dir));
        expect(root.existsSync(), isTrue, reason: '$dir/ must exist');
        final sources = root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        expect(
          sources,
          isNotEmpty,
          reason: 'the guard must scan real sources, not an empty list',
        );
        for (final file in sources) {
          for (final line in file.readAsLinesSync()) {
            final trimmed = line.trim();
            if (!trimmed.startsWith('import ') &&
                !trimmed.startsWith('export ')) {
              continue;
            }
            if (trimmed.contains('package:flutter/') ||
                trimmed.contains('package:flutter_test/') ||
                trimmed.contains('dart:ui')) {
              offenders.add('${file.path}: $trimmed');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'crux_policy must never import Flutter. Found:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no dependency drags Flutter in transitively', () {
      // The pubspec check above catches a DIRECT dependency. This catches the
      // one that arrives through a sibling — a `crux_*` package that grows a
      // Flutter dependency one day — which is precisely how `crux_license`
      // ended up needing a second barrel.
      //
      // It walks pubspecs rather than the resolved package list, because this
      // is a pub workspace: the root `package_config.json` is shared with
      // thirty Flutter packages and so says nothing about what *this* package
      // can reach.
      final locations = _packageLocations(packageRoot);
      if (locations == null) {
        fail(
          'the workspace is not bootstrapped, so this guard cannot run. Run '
          '`melos bootstrap` at the crux-shared root — a guard that silently '
          'skips is not a guard',
        );
      }

      final chains = <String, List<String>>{
        'crux_policy': ['crux_policy'],
      };
      final queue = <String>['crux_policy'];
      final offenders = <String>[];
      while (queue.isNotEmpty) {
        final name = queue.removeAt(0);
        final chain = chains[name]!;
        for (final dependency in _runtimeDependenciesOf(locations, name)) {
          if (const {
            'flutter',
            'flutter_test',
            'sky_engine',
          }.contains(dependency)) {
            offenders.add([...chain, dependency].join(' -> '));
            continue;
          }
          if (chains.containsKey(dependency)) continue;
          chains[dependency] = [...chain, dependency];
          queue.add(dependency);
        }
      }

      expect(
        chains.keys,
        containsAll(<String>['crux_signing', 'meta', 'path']),
        reason: 'the walk must reach real dependencies, not stop at the root',
      );
      expect(
        offenders,
        isEmpty,
        reason:
            'a route from crux_policy to Flutter breaks `dart build cli`. '
            'Found:\n${offenders.join('\n')}',
      );
    });
    test('no route from crux_policy to crux_license', () {
      // telemetry, license and updateChannel must resolve BEFORE a
      // licence exists, because the first-launch telemetry disclosure fires
      // before any key has been entered and the tier is unknown at that instant
      // by construction. A dependency edge from here to the licence machinery
      // is how a tier lookup creeps into the one path that cannot have one —
      // and it would look like it works, because in development a licence is
      // always already there.
      final locations = _packageLocations(packageRoot);
      if (locations == null) fail('workspace is not bootstrapped');

      final seen = <String>{'crux_policy'};
      final queue = <String>['crux_policy'];
      while (queue.isNotEmpty) {
        for (final dep in _runtimeDependenciesOf(
          locations,
          queue.removeAt(0),
        )) {
          if (seen.add(dep)) queue.add(dep);
        }
      }
      expect(
        seen,
        contains('crux_signing'),
        reason: 'the walk must reach real dependencies',
      );
      expect(
        seen,
        isNot(contains('crux_license')),
        reason:
            'crux_policy resolves keys that must work with no licence present',
      );
    });
  });
}

/// Maps package name to its resolved root directory, from the workspace's
/// `package_config.json`. Returns `null` when nothing is resolved yet.
Map<String, String>? _packageLocations(Directory packageRoot) {
  for (var dir = packageRoot; ; dir = dir.parent) {
    final config = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      final decoded =
          jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      final base = Uri.file('${config.parent.path}${p.separator}');
      return <String, String>{
        for (final entry
            in (decoded['packages']! as List<Object?>)
                .cast<Map<String, Object?>>())
          entry['name']! as String: base
              .resolve(entry['rootUri']! as String)
              .toFilePath(),
      };
    }
    if (dir.path == dir.parent.path) return null;
  }
}

/// The `dependencies:` (not `dev_dependencies:`) declared by [name].
Set<String> _runtimeDependenciesOf(Map<String, String> locations, String name) {
  final root = locations[name];
  if (root == null) return const {};
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const {};
  final doc = loadYaml(pubspec.readAsStringSync());
  if (doc is! YamlMap) return const {};
  final deps = doc['dependencies'];
  if (deps is! YamlMap) return const {};
  return deps.keys.cast<Object?>().map((k) => k.toString()).toSet();
}
