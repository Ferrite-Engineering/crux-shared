// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guard for the Flutter-free `crux_license_core.dart` barrel.
//
// WHAT IT LOCKS
// `crux_license_core.dart` exists so a headless entry point — LintCrux's Pro
// CLI today, every product's eventually — can gate Pro subcommands without
// pulling `dart:ui` into an AOT kernel. That property is invisible in a
// Flutter app: `flutter test` links the engine, so a barrel that quietly
// re-acquires Flutter still passes every behavioral test in this package and
// only fails months later, at a product's `dart build cli`, as an FFI
// transformer crash with no source location. This file makes the regression
// fail here instead.
//
// TWO INDEPENDENT CHECKS, DELIBERATELY
//  1. An END-TO-END proof: the standalone Dart VM runs
//     `test/headless/core_barrel_probe.dart`, which imports only the core
//     barrel and touches a symbol from every export. The VM ships no
//     `dart:ui`, so this reproduces the exact compile the CLI performs. It is
//     the strongest evidence available — but it needs a `dart` executable, so
//     it cannot be the only check.
//  2. A STATIC transitive-import-closure scan, which needs nothing but the
//     source tree and therefore always runs.
//
// A pure `dart test` for this package is not possible: `crux_license` declares
// the Flutter SDK in its pubspec, so `dart pub get` cannot resolve it and
// `melos run test` correctly routes the package to `flutter test`. The
// subprocess probe is how the pure-Dart compilation still gets exercised.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Import prefixes that would put Flutter (and therefore `dart:ui`) back into
/// the core barrel's closure. `riverpod` is included because this package's
/// Riverpod dependency is `flutter_riverpod`, which is itself a Flutter
/// package.
const List<String> _forbidden = <String>[
  'dart:ui',
  'dart:ui_web',
  'dart:html',
  'package:flutter/',
  'package:flutter_test/',
  'package:flutter_localizations/',
  'riverpod',
];

void main() {
  setUpAll(() {
    expect(
      File('lib/crux_license_core.dart').existsSync(),
      isTrue,
      reason: 'run this test from the crux_license package root (flutter test)',
    );
  });

  group('crux_license_core is Flutter-free', () {
    test('the standalone Dart VM can run a program importing only it', () {
      final dart = _dartExecutable();
      expect(
        dart,
        isNotNull,
        reason:
            'no standalone `dart` executable found (looked at FLUTTER_ROOT, '
            'the running SDK, and PATH). The end-to-end proof cannot run; '
            'the static closure check below still does.',
      );

      final result = Process.runSync(dart!, <String>[
        'run',
        p.join('test', 'headless', 'core_barrel_probe.dart'),
      ], workingDirectory: Directory.current.path);

      expect(
        result.exitCode,
        0,
        reason:
            'A program importing only '
            '`package:crux_license/crux_license_core.dart` failed to '
            'compile/run on the standalone Dart VM. That means Flutter is '
            "back in the barrel's transitive import closure — the exact "
            'regression this barrel exists to prevent, and the one that '
            'kills `dart build cli` in the products.\n'
            'stdout: ${result.stdout}\n'
            'stderr: ${result.stderr}',
      );
      expect(
        result.stdout.toString(),
        contains('tier=pro'),
        reason: 'the probe ran but did not produce its expected output',
      );
    });

    test('no file reachable from the barrel imports Flutter', () {
      final closure = _importClosure('lib/crux_license_core.dart');

      expect(
        closure.length,
        greaterThanOrEqualTo(7),
        reason:
            'sanity: the closure walk found only ${closure.length} '
            'libraries, so it is not actually following the barrel',
      );

      final offenders = <String>[];
      for (final file in closure) {
        for (final directive in _directives(File(file))) {
          for (final bad in _forbidden) {
            if (directive.contains(bad)) {
              offenders.add('${p.relative(file)}: $directive');
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'crux_license_core.dart must stay importable from a `dart build '
            'cli` entry point. Move the offending symbol behind the main '
            '`crux_license.dart` barrel instead of exporting it here:\n'
            '${offenders.join('\n')}',
      );
    });

    // Guards the guard: if the Dart VM tolerated Flutter imports, check (1)
    // would pass for any barrel and prove nothing. The main barrel — which is
    // Flutter by design — must fail the very same probe.
    test('the check is not vacuous: the Flutter barrel fails the probe', () {
      final dart = _dartExecutable();
      if (dart == null) return;

      final probe =
          File(
            p.join('test', 'headless', '.flutter_barrel_probe.dart'),
          )..writeAsStringSync(
            "import 'package:crux_license/crux_license.dart';\n"
            'void main() => print(LicenseTier.pro.name);\n',
          );
      addTearDown(() {
        if (probe.existsSync()) probe.deleteSync();
      });

      final result = Process.runSync(dart, <String>[
        'run',
        probe.path,
      ], workingDirectory: Directory.current.path);

      expect(
        result.exitCode,
        isNot(0),
        reason:
            'the standalone Dart VM accepted a program importing the Flutter '
            'barrel, so the headless probe above no longer proves anything. '
            'Either the main barrel stopped importing Flutter (then this '
            'guard needs rethinking) or the toolchain changed.',
      );
    });
  });

  // FeatureGate.isAvailable reads the compile-time kBetaPeriod, which no
  // provider override reaches, so the in-process suite can only run the
  // branch its own build selects. Compiling the probe once per define runs
  // both on every invocation: it prints the flag and the gate's answer for a
  // Pro feature at the Open Core tier, and the define is the whole difference
  // between the two runs.
  group('the beta short-circuit, pinned by define', () {
    for (final beta in <bool>[true, false]) {
      test('BETA_PERIOD=$beta ${beta ? 'opens' : 'enforces'} the gate', () {
        final dart = _dartExecutable();
        expect(
          dart,
          isNotNull,
          reason: 'no standalone `dart` executable found to run the probe',
        );

        final result = Process.runSync(dart!, <String>[
          'run',
          '-DBETA_PERIOD=$beta',
          p.join('test', 'headless', 'core_barrel_probe.dart'),
        ], workingDirectory: Directory.current.path);

        expect(
          result.exitCode,
          0,
          reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
        final out = result.stdout.toString();
        expect(out, contains('beta=$beta'));
        expect(
          out,
          contains('gate=$beta'),
          reason: beta
              ? 'a beta build unlocks every feature regardless of tier'
              : 'outside the beta, a Pro feature is closed at Open Core',
        );
      });
    }
  });

  group('the two barrels cannot drift apart', () {
    test('every core export is also exported by crux_license.dart', () {
      final core = _exportedSrcPaths('lib/crux_license_core.dart');
      final main = _exportedSrcPaths('lib/crux_license.dart');

      expect(core, isNotEmpty, reason: 'the core barrel exports nothing');
      expect(
        core.difference(main),
        isEmpty,
        reason:
            'the core barrel exports something the main barrel does not, so a '
            'Flutter host would need both imports and the two goldens under '
            'api/ would describe divergent surfaces. Add the export to '
            'crux_license.dart too.',
      );
    });
  });
}

/// The `src/…` paths a barrel re-exports, as written in its directives.
Set<String> _exportedSrcPaths(String barrel) {
  final out = <String>{};
  final pattern = RegExp(r"^export\s+'([^']+)'");
  for (final line in File(barrel).readAsLinesSync()) {
    final match = pattern.firstMatch(line.trim());
    if (match != null) out.add(match.group(1)!);
  }
  return out;
}

/// Every `lib/` file reachable from [entry] through `import` / `export` /
/// `part`, following both relative and `package:crux_license/…` forms.
Set<String> _importClosure(String entry) {
  final seen = <String>{};
  final queue = <String>[p.normalize(File(entry).absolute.path)];
  final libRoot = Directory('lib').absolute.path;

  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!seen.add(current)) continue;
    final file = File(current);
    if (!file.existsSync()) continue;

    for (final directive in _directives(file)) {
      final match = RegExp("'([^']+)'").firstMatch(directive);
      if (match == null) continue;
      final uri = match.group(1)!;
      String? resolved;
      if (uri.startsWith('package:crux_license/')) {
        resolved = p.join(
          libRoot,
          uri.substring('package:crux_license/'.length),
        );
      } else if (!uri.contains(':')) {
        resolved = p.join(p.dirname(current), uri);
      }
      // Anything else (`dart:`, another package) is a leaf: it is checked as
      // a directive above but not walked into.
      if (resolved != null) queue.add(p.normalize(resolved));
    }
  }
  return seen;
}

/// The `import` / `export` / `part` directive lines of [file], with comment
/// lines dropped so a doc comment naming `package:flutter/material.dart`
/// cannot trip the scan.
List<String> _directives(File file) {
  final out = <String>[];
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.startsWith('//') || line.startsWith('///')) continue;
    if (line.startsWith('import ') ||
        line.startsWith('export ') ||
        line.startsWith('part ')) {
      out.add(line);
    }
  }
  return out;
}

/// A standalone `dart` executable. Under `flutter test` the running executable
/// is the Flutter tester, not the Dart VM, so the bundled SDK is located
/// explicitly before falling back to `PATH`.
String? _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';
  final candidates = <String>[
    if (flutterRoot != null)
      p.join(flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin', exe),
    if (flutterRoot != null) p.join(flutterRoot, 'bin', exe),
    p.join(p.dirname(p.dirname(Platform.resolvedExecutable)), 'bin', exe),
    p.join(p.dirname(Platform.resolvedExecutable), exe),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  final which = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    <String>[
      'dart',
    ],
  );
  if (which.exitCode == 0) {
    final first = which.stdout.toString().trim().split('\n').first.trim();
    if (first.isNotEmpty && File(first).existsSync()) return first;
  }
  return null;
}
