// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:test/test.dart';

void main() {
  group('appendMissingPathDirs', () {
    test('appends missing dirs after existing entries, preserving order', () {
      final result = appendMissingPathDirs(
        '/usr/bin:/bin',
        const <String>['/opt/homebrew/bin', '/usr/local/bin'],
        separator: ':',
        caseInsensitive: false,
      );
      expect(result, '/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin');
    });

    test('returns null when every extra dir is already present', () {
      final result = appendMissingPathDirs(
        '/usr/bin:/opt/homebrew/bin:/usr/local/bin',
        const <String>['/opt/homebrew/bin', '/usr/local/bin'],
        separator: ':',
        caseInsensitive: false,
      );
      expect(result, isNull);
    });

    test('appends only the dirs that are missing', () {
      final result = appendMissingPathDirs(
        '/opt/homebrew/bin:/usr/bin',
        const <String>['/opt/homebrew/bin', '/usr/local/bin'],
        separator: ':',
        caseInsensitive: false,
      );
      expect(result, '/opt/homebrew/bin:/usr/bin:/usr/local/bin');
    });

    test('handles an empty current PATH', () {
      final result = appendMissingPathDirs(
        '',
        const <String>[r'C:\tools\bin'],
        separator: ';',
        caseInsensitive: true,
      );
      expect(result, r'C:\tools\bin');
    });

    test('uses the Windows separator and case-insensitive dedup', () {
      // The existing entry differs only in case + drive-letter case; a
      // Windows-correct dedup must treat it as already present and append
      // only the genuinely new dir.
      final result = appendMissingPathDirs(
        r'c:\users\me\oss-cad-suite\BIN;C:\Windows\System32',
        const <String>[
          r'C:\Users\me\oss-cad-suite\bin', // already present (case-fold)
          r'C:\Users\me\oss-cad-suite\lib', // new
        ],
        separator: ';',
        caseInsensitive: true,
      );
      expect(
        result,
        r'c:\users\me\oss-cad-suite\BIN;C:\Windows\System32;'
        r'C:\Users\me\oss-cad-suite\lib',
      );
    });

    test('case-sensitive mode does not fold case (POSIX)', () {
      final result = appendMissingPathDirs(
        '/usr/BIN',
        const <String>['/usr/bin'],
        separator: ':',
        caseInsensitive: false,
      );
      // '/usr/bin' != '/usr/BIN' under case-sensitive compare, so appended.
      expect(result, '/usr/BIN:/usr/bin');
    });

    test('drops empty segments from a trailing/duplicate separator', () {
      final result = appendMissingPathDirs(
        '/usr/bin::',
        const <String>['/new'],
        separator: ':',
        caseInsensitive: false,
      );
      expect(result, '/usr/bin:/new');
    });
  });

  group('parseWindowsPersistentPath', () {
    // The shape `reg query <key> /v Path` prints: a blank line, the key, the
    // value line, a blank line.
    const header = '\r\nHKEY_CURRENT_USER\\Environment\r\n';

    test('splits a REG_SZ value on semicolons', () {
      final dirs = parseWindowsPersistentPath(
        '$header    Path    REG_SZ    C:\\tools\\bin;C:\\oss-cad-suite\\bin\r\n',
        environment: const <String, String>{},
      );
      expect(dirs, <String>[r'C:\tools\bin', r'C:\oss-cad-suite\bin']);
    });

    test('expands %VAR% references in a REG_EXPAND_SZ value', () {
      final dirs = parseWindowsPersistentPath(
        '$header    Path    REG_EXPAND_SZ    '
        '%USERPROFILE%\\bin;%SystemRoot%\\system32\r\n',
        environment: const <String, String>{'USERPROFILE': r'C:\Users\me'},
      );
      // A known variable expands; an unknown one is left intact rather than
      // collapsed to an empty segment that would then be dropped.
      expect(dirs, <String>[r'C:\Users\me\bin', r'%SystemRoot%\system32']);
    });

    test('drops empty segments and trims whitespace', () {
      final dirs = parseWindowsPersistentPath(
        '$header    Path    REG_SZ    C:\\a; ;C:\\b;\r\n',
        environment: const <String, String>{},
      );
      expect(dirs, <String>[r'C:\a', r'C:\b']);
    });

    test('does not match PATHEXT or a path that merely contains Path', () {
      final dirs = parseWindowsPersistentPath(
        '$header    PATHEXT    REG_SZ    .COM;.EXE\r\n'
        '    MyPath    REG_SZ    C:\\nope\r\n',
        environment: const <String, String>{},
      );
      expect(dirs, isEmpty);
    });

    test('returns nothing for output without a Path value', () {
      final dirs = parseWindowsPersistentPath(
        'ERROR: The system was unable to find the specified registry key.',
        environment: const <String, String>{},
      );
      expect(dirs, isEmpty);
    });
  });

  group('engineSearchDirs', () {
    test('platform-appropriate search dirs', () {
      resetEngineSearchDirsCacheForTesting();
      final dirs = engineSearchDirs();
      if (Platform.isMacOS) {
        expect(dirs, <String>['/opt/homebrew/bin', '/usr/local/bin']);
      } else if (Platform.isWindows) {
        // Reads the persistent registry PATH — a real Windows dev box has a
        // non-empty PATH. Every entry is a non-empty string.
        expect(dirs, isNotEmpty);
        expect(dirs.every((d) => d.isNotEmpty), isTrue);
      } else {
        // Linux inherits the desktop-session PATH normally.
        expect(dirs, isEmpty);
      }
    });

    test('repeated calls return one list, not one registry read each', () {
      // On macOS and Linux the answer is a const list, so identity holds by
      // construction; on Windows it holds because the registry read is
      // cached for the process lifetime. Either way a spawn loop calling
      // this per engine must not pay for a `reg query` each time.
      resetEngineSearchDirsCacheForTesting();
      final first = engineSearchDirs();
      expect(identical(engineSearchDirs(), first), isTrue);
    });
  });
}
