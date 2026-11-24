// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `crux_telemetry_core` is pure Dart, permanently.
///
/// The products' headless binaries (`dart build cli`) and `crux_mcp` link it,
/// and a Flutter import anywhere in the graph drags `dart:ui` into the AOT
/// kernel and kills that compile. So: no `flutter:` dependency, no Flutter
/// import, and no package that brings one in, which rules out
/// `crux_telemetry` and `crux_license` (both Flutter packages; the first
/// depends on this one, never the reverse).
void main() {
  final packageRoot = Directory.current;

  group('crux_telemetry_core stays pure Dart', () {
    test('the pubspec declares no Flutter dependency', () {
      final pubspec = File(p.join(packageRoot.path, 'pubspec.yaml'));
      expect(pubspec.existsSync(), isTrue);
      expect(
        RegExp(
          r'^\s{2}flutter\s*:',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync()),
        isFalse,
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
        expect(sources, isNotEmpty);
        for (final file in sources) {
          for (final line in file.readAsLinesSync()) {
            final trimmed = line.trim();
            if (!trimmed.startsWith('import ') &&
                !trimmed.startsWith('export ')) {
              continue;
            }
            if (trimmed.contains('package:flutter/') ||
                trimmed.contains('package:flutter_test/') ||
                trimmed.contains('package:flutter_riverpod/') ||
                trimmed.contains('package:path_provider/') ||
                trimmed.contains('dart:ui')) {
              offenders.add('${file.path}: $trimmed');
            }
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('no dependency drags Flutter in transitively', () {
      final locations = _packageLocations(packageRoot);
      if (locations == null) {
        fail(
          'the workspace is not bootstrapped, so this guard cannot run. Run '
          '`melos bootstrap` at the crux-shared root',
        );
      }
      final chains = <String, List<String>>{
        'crux_telemetry_core': ['crux_telemetry_core'],
      };
      final queue = <String>['crux_telemetry_core'];
      final offenders = <String>[];
      while (queue.isNotEmpty) {
        final name = queue.removeAt(0);
        final chain = chains[name]!;
        for (final dependency in _runtimeDependenciesOf(locations, name)) {
          if (const {'flutter', 'flutter_test', 'sky_engine'}.contains(
            dependency,
          )) {
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
        containsAll(<String>['http', 'meta', 'path']),
        reason: 'the walk must reach real dependencies, not stop at the root',
      );
      expect(
        chains.keys,
        isNot(anyOf(contains('crux_license'), contains('crux_telemetry'))),
        reason: 'both are Flutter packages',
      );
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}

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
