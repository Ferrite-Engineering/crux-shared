// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: no package opens a link with `launchUrl`, or reveals a file
// with `revealInFileManager`, except through crux_ide_layout's `cruxOpenUrl`
// and `cruxRevealFile`.
//
// Both answer false when nothing opened: a Linux host displayed remotely
// often has no browser to hand a link to and no file manager to show a file
// in. A caller that drops the answer leaves the user clicking at a control
// that does nothing and says nothing. The two wrappers report it (an error
// toast naming the address or the path, with Copy), so a bare call is the
// silent failure coming back.
//
// Comment text is skipped. `crux_io` defines the reveal, and
// `external_open.dart` is the one place each is called.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _launchRe = RegExp(r'\blaunchUrl(?:String)?\b');
final _revealRe = RegExp(r'\brevealInFileManager\b');

/// The wrapper itself, the one file allowed to name both.
const _wrapper = 'crux_ide_layout/lib/src/external_open.dart';

String _code(String source) => source
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

void main() {
  test('links and reveals go through cruxOpenUrl and cruxRevealFile', () {
    final packages = Directory(
      p.normalize(p.join(Directory.current.path, '..')),
    );
    final findings = <String>[];
    for (final pkg in packages.listSync().whereType<Directory>()) {
      final lib = Directory(p.join(pkg.path, 'lib'));
      if (!lib.existsSync()) continue;
      final name = p.basename(pkg.path);
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final rel = p.posix.joinAll(
          p.split(p.relative(file.path, from: packages.path)),
        );
        if (rel == _wrapper) continue;
        final code = _code(file.readAsStringSync());
        if (_launchRe.hasMatch(code)) {
          findings.add('$rel names launchUrl; call cruxOpenUrl instead.');
        }
        if (name != 'crux_io' && _revealRe.hasMatch(code)) {
          findings.add(
            '$rel names revealInFileManager; call cruxRevealFile instead.',
          );
        }
      }
    }
    expect(findings, isEmpty, reason: findings.join('\n'));
  });
}
