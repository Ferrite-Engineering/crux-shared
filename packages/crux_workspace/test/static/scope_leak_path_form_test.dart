// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The scope-leak scanner reports call sites and library paths, and a product's
// allowlist names them with forward slashes. On Windows the host separator is
// a backslash, so a path taken from the host unchanged never matched an
// allowlist entry. Windows CI runs weekly; these tests run the Windows path
// forms on every host, on every push.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'route_mounted_scope_leak_guard.dart';
import 'scope_leak_scanner.dart';

void main() {
  group('posixRelative', () {
    test('writes a Windows path with forward slashes', () {
      expect(
        posixRelative(
          r'C:\work\app\lib\features\palette\palette_dialog.dart',
          context: p.windows,
          from: r'C:\work\app',
        ),
        'lib/features/palette/palette_dialog.dart',
      );
    });

    test('reads a Windows path written with mixed separators', () {
      expect(
        posixRelative(
          r'C:\work\app/lib\features/palette\palette_dialog.dart',
          context: p.windows,
          from: r'C:\work\app',
        ),
        'lib/features/palette/palette_dialog.dart',
      );
    });

    test('leaves a POSIX path as it is', () {
      expect(
        posixRelative(
          '/work/app/lib/features/palette/palette_dialog.dart',
          context: p.posix,
          from: '/work/app',
        ),
        'lib/features/palette/palette_dialog.dart',
      );
    });

    test('the host default agrees with the explicit host context', () {
      final path = p.join(p.current, 'lib', 'a', 'b.dart');
      expect(posixRelative(path), 'lib/a/b.dart');
      expect(posixRelative(path), posixRelative(path, context: p.context));
    });
  });

  group('posixSeparators', () {
    test('turns either separator into a forward slash', () {
      expect(posixSeparators(r'lib\a\b.dart:4'), 'lib/a/b.dart:4');
      expect(posixSeparators('lib/a/b.dart:4'), 'lib/a/b.dart:4');
      expect(
        posixSeparators(r'Dialog @ lib\a/b.dart:4'),
        'Dialog @ lib/a/b.dart:4',
      );
    });
  });

  group('the scanner over the pinned shapes', () {
    late final ScopeGraph shapes;
    late final Set<String> perTab;

    setUpAll(() async {
      shapes = await ScopeGraph.resolve(<Directory>[
        Directory('test/static/route_scope_shapes'),
      ]);
      perTab = <String>{shapes.keyOf('perTabProvider')!};
    });

    test('reports no backslash in any call site or library path', () {
      final mounts = shapes.routeMounts();
      expect(mounts, isNotEmpty);
      for (final mount in mounts) {
        expect(mount.callSite, isNot(contains(r'\')));
        expect(mount.widgetPath ?? '', isNot(contains(r'\')));
      }
      for (final provider in shapes.providers.values) {
        expect(provider.path, isNot(contains(r'\')));
      }
    });

    test('an allowlist written with Windows separators still matches', () {
      final found = routeScopeViolations(shapes, perTab);
      expect(found, isNotEmpty);
      final target = found.first;
      final windowsKey = target.allowlistKey.replaceAll('/', r'\');
      expect(windowsKey, isNot(target.allowlistKey));

      final after = routeScopeViolations(
        shapes,
        perTab,
        allowlist: <String, String>{windowsKey: 'a justification'},
      );
      expect(
        after.map((v) => v.allowlistKey),
        isNot(contains(target.allowlistKey)),
      );
      expect(after, hasLength(found.length - 1));
    });

    test('a scope-key library given with Windows separators seeds the '
        'same providers', () {
      final library = shapes.providers.values.first.path;
      final posix = routeScopePerTabProviders(shapes, scopeKeyLibrary: library);
      final windows = routeScopePerTabProviders(
        shapes,
        scopeKeyLibrary: library.replaceAll('/', r'\'),
      );
      expect(windows, posix);
      expect(posix, isNotEmpty);
    });
  });
}
