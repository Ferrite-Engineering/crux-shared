// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Riverpod-free guard.
///
/// crux-shared accepts a Riverpod coupling in general — five of its
/// packages hard-depend on `flutter_riverpod`. `crux_cxp` is the stated
/// exception, and the reason is specific: it is the package third parties
/// build CXP-compatible tools against once this repo goes public. A
/// protocol binding that drags in a state-management framework is not one
/// a project on Bloc, signals, or plain Dart can adopt — and crux_cxp does
/// not even depend on Flutter.
///
/// The coupling is cheap to acquire by accident (one `import` during a
/// refactor, one transitive dependency added to the pubspec) and expensive
/// to shed after publication. This test makes it impossible to acquire
/// silently.
void main() {
  group('crux_cxp stays free of Riverpod', () {
    // `dart test` runs with the package root as cwd.
    final packageRoot = Directory.current;

    test('the pubspec declares no riverpod dependency', () {
      final pubspec = File('${packageRoot.path}/pubspec.yaml');
      expect(
        pubspec.existsSync(),
        isTrue,
        reason: 'guard must run against the real pubspec, not a stub',
      );
      final lines = pubspec.readAsLinesSync();
      final offenders = <String>[
        for (final line in lines)
          if (line.toLowerCase().contains('riverpod')) line.trim(),
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'crux_cxp must never depend on Riverpod — it is the package '
            'third parties build CXP tools against. Found: $offenders',
      );
    });

    test('the pubspec declares no Flutter dependency either', () {
      // The same argument, one level out: a pure-Dart protocol binding is
      // usable from a CLI, a server, or a non-Flutter GUI.
      final pubspec = File('${packageRoot.path}/pubspec.yaml');
      final text = pubspec.readAsStringSync();
      expect(
        RegExp(r'^\s{2}flutter\s*:', multiLine: true).hasMatch(text),
        isFalse,
        reason: 'crux_cxp must stay pure Dart',
      );
    });

    test('no lib/ source imports riverpod', () {
      final lib = Directory('${packageRoot.path}/lib');
      expect(lib.existsSync(), isTrue, reason: 'lib/ must exist');

      final sources = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(
        sources,
        isNotEmpty,
        reason: 'guard must actually scan sources, not an empty list',
      );

      final offenders = <String>[];
      for (final file in sources) {
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('import ') &&
              !trimmed.startsWith('export ')) {
            continue;
          }
          if (trimmed.toLowerCase().contains('riverpod') ||
              trimmed.contains('package:flutter/')) {
            offenders.add('${file.path}: $trimmed');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'crux_cxp lib/ must not import Riverpod or Flutter. Found:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
