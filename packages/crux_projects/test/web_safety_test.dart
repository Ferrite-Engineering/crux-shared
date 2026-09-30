// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `crux_projects` must stay importable from a Flutter web build.
//
// The persistent registry that once lived here imported `dart:io`, and while
// it was exported from the barrel any import of
// `package:crux_projects/crux_projects.dart` broke a web compile. Both
// consumers (LintCrux, SimCrux) ship a `web/` target and both import the
// barrel from open-core code, so that was a live breakage rather than a
// theoretical one. The registry has since left the package altogether; this
// guard stays, because the next `dart:io` import to land here would break the
// same two products the same way.
//
// A source-level guard rather than a runtime one: the failure mode is a
// compile error in a *downstream* repo's web build, which no unit test in this
// package can otherwise observe. Reachability is computed transitively — an
// intermediate library that pulls in `dart:io` is exactly as fatal as the
// barrel doing it directly.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Entry points that must compile for web. Every top-level `lib/*.dart` is
/// one: a consumer can import it, so it is public API and must be web-safe.
List<String> _entryPoints(String packageRoot) =>
    Directory(p.join(packageRoot, 'lib'))
        .listSync()
        .whereType<File>()
        .map((f) => p.relative(f.path, from: packageRoot))
        .where((f) => f.endsWith('.dart'))
        .toList()
      ..sort();

void main() {
  final packageRoot = _findPackageRoot();

  group('web safety', () {
    test('the main barrel is an entry point', () {
      expect(_entryPoints(packageRoot), contains('lib/crux_projects.dart'));
    });

    for (final entry in _entryPoints(packageRoot)) {
      test('$entry reaches no web-unsafe library', () {
        final offenders = _webUnsafeReachableFrom(packageRoot, entry);
        expect(
          offenders,
          isEmpty,
          reason:
              'These libraries are reachable from $entry and import a '
              'web-unsafe dart: library. A registry that needs the filesystem '
              'belongs to the host that installs it, not to this package:\n  '
              '${offenders.join('\n  ')}',
        );
      });
    }

    test('the guard is not vacuous', () {
      // Prove the scanner sees a `dart:io` import when one exists, so a green
      // run above means "none reachable" rather than "nothing scanned".
      final probe = File(p.join(packageRoot, 'test', 'web_safety_test.dart'));
      expect(
        _directivesIn(probe.readAsStringSync()),
        contains('dart:io'),
        reason: "the directive scanner did not find this file's own import",
      );
    });
  });
}

/// `dart:` libraries that do not exist on the web platform.
const _webUnsafeCoreLibraries = <String>{
  'dart:io',
  'dart:isolate',
  'dart:ffi',
  'dart:mirrors',
  'dart:cli',
};

/// Returns every library reachable from [entry] that imports a web-unsafe
/// `dart:` library, as `<path> -> <dart: library>` strings.
List<String> _webUnsafeReachableFrom(String packageRoot, String entry) {
  final offenders = <String>[];
  final seen = <String>{};
  final queue = <String>[p.normalize(p.join(packageRoot, entry))];

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;

    for (final directive in _directivesIn(file.readAsStringSync())) {
      if (_webUnsafeCoreLibraries.contains(directive)) {
        offenders.add('${p.relative(path, from: packageRoot)} -> $directive');
        continue;
      }
      final resolved = _resolveWithinPackage(packageRoot, path, directive);
      if (resolved != null) queue.add(resolved);
    }
  }
  offenders.sort();
  return offenders;
}

final _directivePattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

Iterable<String> _directivesIn(String source) =>
    _directivePattern.allMatches(source).map((m) => m.group(1)!);

/// Resolves a directive URI to a path inside this package, or null when it
/// points outside it (another package, or a `dart:` library we do not follow).
String? _resolveWithinPackage(String packageRoot, String from, String uri) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:crux_projects/')) {
    return p.normalize(
      p.join(
        packageRoot,
        'lib',
        uri.substring('package:crux_projects/'.length),
      ),
    );
  }
  if (uri.startsWith('package:')) return null;
  return p.normalize(p.join(p.dirname(from), uri));
}

String _findPackageRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate the crux_projects package root');
    }
    dir = parent;
  }
}
