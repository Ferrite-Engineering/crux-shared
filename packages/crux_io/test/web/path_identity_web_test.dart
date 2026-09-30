// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_io/crux_io.dart';
import 'package:test/test.dart';

/// Path identity in a browser, where there is no filesystem, no working
/// directory and no symlinks.
///
/// The products' web builds key tabs and recent items by location the same way
/// desktop builds do, and a location there is an uploaded file's name or a
/// URL. It is already its own identity: these must answer with the string,
/// trimmed, and never throw from `dart:io`.
///
/// Runs only under `dart test -p chrome test/web`, which CI invokes as its own
/// step. The VM suite never loads the stub, so this is the one place the web
/// path is actually executed.
void main() {
  test('the filesystem is not case-insensitive — there is none', () {
    expect(filesystemIsCaseInsensitive, isFalse);
  });

  group('canonicalizePath', () {
    test('returns a bare file name trimmed and otherwise unchanged', () {
      expect(canonicalizePath('  design.vcd \n'), 'design.vcd');
    });

    test('leaves a URL exactly as it names its resource', () {
      // Normalising would rewrite what the URL names: `..` inside a query
      // string is data, and a blob id is opaque.
      const url = 'https://example.com/view?json=a/../b.json';
      expect(canonicalizePath(url), url);
      const blob = 'blob:https://app.example.com/5b1f7c0e';
      expect(canonicalizePath(blob), blob);
    });

    test('keeps dot segments rather than resolving them', () {
      expect(canonicalizePath('a/./b/../c.vcd'), 'a/./b/../c.vcd');
    });

    test('is empty for an empty or blank path', () {
      expect(canonicalizePath('   '), '');
    });
  });

  group('canonicalPathKey', () {
    test('preserves case by default', () {
      expect(canonicalPathKey('Design.VCD'), 'Design.VCD');
    });

    test('folds case only when the caller asks', () {
      expect(
        canonicalPathKey('Design.VCD', caseInsensitive: true),
        'design.vcd',
      );
    });
  });

  group('isSamePath', () {
    test('matches the same location written with surrounding whitespace', () {
      expect(isSamePath('design.vcd', ' design.vcd'), isTrue);
    });

    test('does not match different case unless asked to', () {
      expect(isSamePath('design.vcd', 'Design.vcd'), isFalse);
      expect(
        isSamePath('design.vcd', 'Design.vcd', caseInsensitive: true),
        isTrue,
      );
    });

    test('two blank paths are still not the same file', () {
      expect(isSamePath('', '  '), isFalse);
    });
  });

  test('revealInFileManager reports that nothing was revealed', () async {
    expect(await revealInFileManager('design.vcd'), isFalse);
  });
}
