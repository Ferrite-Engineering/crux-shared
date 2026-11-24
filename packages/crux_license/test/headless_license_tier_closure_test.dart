// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guard: the headless resolver (`crux_license_headless.dart`) has no Flutter
// in its import closure.
//
// The resolver is what a product's `dart build cli` binary and MCP server
// link, so Flutter anywhere in its closure kills those builds with an FFI
// transformer crash and no source location, long after this package's own
// `flutter test` run passed. Two independent checks, as for the core barrel
// (`crux_license_core_test.dart`):
//  1. the standalone Dart VM, which has no `dart:ui`, runs
//     `test/headless/headless_barrel_probe.dart`, which imports only the
//     headless and core barrels and resolves a licence for real, once per
//     `BETA_PERIOD` define;
//  2. a static walk of the closure that follows this package and every
//     crux-shared package it reaches (`crux_policy`, `crux_signing`,
//     `crux_io`, ...), so a Flutter import in a sibling package fails here
//     too.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _barrel = 'lib/crux_license_headless.dart';

/// Imports that would put Flutter (and so `dart:ui`) into the closure.
/// `riverpod` because this package's Riverpod is `flutter_riverpod`.
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
      File(_barrel).existsSync(),
      isTrue,
      reason: 'run this test from the crux_license package root (flutter test)',
    );
  });

  group('crux_license_headless is Flutter-free', () {
    for (final beta in <bool>[true, false]) {
      test('the standalone Dart VM runs the resolver, BETA_PERIOD=$beta', () {
        final dart = _dartExecutable();
        expect(dart, isNotNull, reason: 'no standalone `dart` executable');

        final probe = p.join('test', 'headless', 'headless_barrel_probe.dart');
        final result = Process.runSync(dart!, <String>[
          'run',
          '-DBETA_PERIOD=$beta',
          probe,
          File(probe).absolute.path,
        ], workingDirectory: Directory.current.path);

        expect(
          result.exitCode,
          0,
          reason:
              'a program importing only the headless and core barrels failed '
              'on the standalone Dart VM, so Flutter is in the closure of the '
              'resolver.\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
        final out = result.stdout.toString();
        expect(out, contains('env=WAVECRUX_LICENSE_FILE'));
        // Not a licence: the real reader read it and the production
        // validator refused it, so the run is Open Core.
        expect(out, contains('tier=openCore'));
        expect(out, contains('malformed=true'));
        expect(out, contains('beta=$beta'));
        expect(
          out,
          contains('admits=$beta'),
          reason: beta
              ? 'a beta build admits every tier, headless as in the app'
              : 'outside the beta, Open Core does not admit a Pro tool',
        );
      });
    }

    test('no library reachable from the barrel imports Flutter', () {
      final closure = _importClosure(_barrel);
      final names = closure.map(p.basename).toSet();

      // Sanity: the walk really follows the resolver into both packages.
      expect(names, contains('headless_license_tier.dart'));
      expect(names, contains('license_validator.dart'));
      expect(names, contains('policy_loader.dart'));
      expect(names, contains('ed25519.dart'));

      final offenders = <String>[
        for (final file in closure)
          for (final uri in _directiveUris(File(file)))
            for (final bad in _forbidden)
              if (uri.contains(bad)) '${p.relative(file)}: $uri',
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'the headless resolver must stay linkable from a `dart build cli` '
            'entry point:\n${offenders.join('\n')}',
      );
    });

    test('the walk is not vacuous: it reports a Flutter import', () {
      final dir = Directory.systemTemp.createTempSync('headless_closure_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final entry = File(p.join(dir.path, 'entry.dart'))
        ..writeAsStringSync(
          "import 'leaf.dart';\n"
          '// import ignored in a comment\n',
        );
      File(p.join(dir.path, 'leaf.dart')).writeAsStringSync(
        "export 'stub.dart'\n"
        "    if (dart.library.io) 'package:flutter/widgets.dart';\n",
      );
      final closure = _importClosure(entry.path);
      final uris = <String>[
        for (final file in closure) ..._directiveUris(File(file)),
      ];
      expect(uris, contains('package:flutter/widgets.dart'));
    });
  });
}

/// Every library reachable from [entry] through `import`, `export` and
/// `part`, following relative URIs and `package:` URIs of the crux-shared
/// packages beside this one. Anything else (`dart:`, a third-party package)
/// is a leaf: its URI is checked but not walked.
Set<String> _importClosure(String entry) {
  final packagesDir = Directory.current.parent.absolute.path;
  final seen = <String>{};
  final queue = <String>[p.normalize(File(entry).absolute.path)];

  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    final file = File(current);
    if (seen.contains(current) || !file.existsSync()) continue;
    seen.add(current);

    for (final uri in _directiveUris(file)) {
      String? resolved;
      if (uri.startsWith('package:')) {
        final rest = uri.substring('package:'.length);
        final slash = rest.indexOf('/');
        final package = rest.substring(0, slash);
        final lib = p.join(packagesDir, package, 'lib');
        if (Directory(lib).existsSync()) {
          resolved = p.join(lib, rest.substring(slash + 1));
        }
      } else if (!uri.contains(':')) {
        resolved = p.join(p.dirname(current), uri);
      }
      if (resolved != null) queue.add(p.normalize(resolved));
    }
  }
  return seen;
}

/// The URIs named by [file]'s `import`, `export` and `part` directives,
/// conditional ones included, with comment lines dropped first so a doc
/// comment naming a Flutter library cannot trip the scan.
List<String> _directiveUris(File file) {
  final code = file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  final directive = RegExp(
    r'^\s*(?:import|export|part)\s[^;]*;',
    multiLine: true,
  );
  final quoted = RegExp('''['"]([^'"]+)['"]''');
  return <String>[
    for (final match in directive.allMatches(code))
      for (final uri in quoted.allMatches(match.group(0)!)) uri.group(1)!,
  ];
}

/// A standalone `dart` executable. Under `flutter test` the running executable
/// is the Flutter tester, so the bundled SDK is looked for first.
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
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', [
    'dart',
  ]);
  if (which.exitCode == 0) {
    final first = which.stdout.toString().trim().split('\n').first.trim();
    if (first.isNotEmpty && File(first).existsSync()) return first;
  }
  return null;
}
