// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/src/engine_path_augmentation.dart';
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

  group('prependPathDirs', () {
    test('moves the dirs to the front, dropping their later copies', () {
      expect(
        prependPathDirs(
          r'C:\Git\mingw64\bin;c:\oss\BIN;C:\Windows;C:\oss\lib',
          const <String>[r'C:\oss\bin', r'C:\oss\lib'],
          separator: ';',
          caseInsensitive: true,
        ),
        r'C:\oss\bin;C:\oss\lib;C:\Git\mingw64\bin;C:\Windows',
      );
    });

    test('returns null when the path already starts with the dirs', () {
      expect(
        prependPathDirs(
          r'C:\oss\bin;C:\oss\lib;C:\Windows',
          const <String>[r'C:\oss\bin', r'C:\oss\lib'],
          separator: ';',
          caseInsensitive: true,
        ),
        isNull,
      );
    });
  });

  group('ossCadSuiteSpawnEnvironment', () {
    // A fake Windows filesystem: one OSS CAD Suite install, and an unrelated
    // bin/lib pair without environment.bat.
    const files = <String>{
      r'C:\Users\me\oss-cad-suite\environment.bat',
      r'C:\Users\me\oss-cad-suite\bin\yosys.exe',
      r'C:\tools\bin\yosys.exe',
    };
    const dirs = <String>{r'C:\Users\me\oss-cad-suite\lib', r'C:\tools\lib'};
    // The user's PATH has the suite's bin and lib, but after a toolchain
    // that ships same-named DLLs.
    const parent = <String, String>{
      'Path':
          r'C:\Git\mingw64\bin;C:\Users\me\oss-cad-suite\bin;'
          r'C:\Users\me\oss-cad-suite\lib',
      'USERPROFILE': r'C:\Users\me',
    };

    Map<String, String>? envFor(
      String exe, {
      Map<String, String>? environment,
      bool windows = true,
    }) => ossCadSuiteSpawnEnvironment(
      exe,
      environment,
      windows: windows,
      parentEnvironment: parent,
      isFile: files.contains,
      isDirectory: dirs.contains,
    );

    test('puts the install bin and lib first for its own binary', () {
      final env = envFor(r'C:\Users\me\oss-cad-suite\bin\yosys.exe');
      expect(
        env!['Path'],
        r'C:\Users\me\oss-cad-suite\bin;C:\Users\me\oss-cad-suite\lib;'
        r'C:\Git\mingw64\bin',
      );
      expect(env['USERPROFILE'], r'C:\Users\me');
    });

    test('adjusts a caller-built environment rather than the parent', () {
      final env = envFor(
        r'C:\Users\me\oss-cad-suite\bin\yosys.exe',
        environment: const <String, String>{
          'PATH': r'C:\elsewhere',
          'NO_COLOR': '1',
        },
      );
      expect(env, <String, String>{
        'PATH':
            r'C:\Users\me\oss-cad-suite\bin;C:\Users\me\oss-cad-suite\lib;'
            r'C:\elsewhere',
        'NO_COLOR': '1',
      });
    });

    test('leaves a binary outside an OSS CAD Suite install alone', () {
      expect(envFor(r'C:\tools\bin\yosys.exe'), isNull);
      const given = <String, String>{'PATH': r'C:\x'};
      expect(
        identical(envFor(r'C:\tools\bin\yosys.exe', environment: given), given),
        isTrue,
      );
    });

    test('does nothing off Windows', () {
      expect(
        envFor(r'C:\Users\me\oss-cad-suite\bin\yosys.exe', windows: false),
        isNull,
      );
    });

    test('does nothing for a bare name', () {
      expect(envFor('yosys.exe'), isNull);
    });
  });

  group('engineSearchDirs', () {
    test('platform-appropriate search dirs', () {
      resetEngineSearchDirsCacheForTesting();
      final dirs = engineSearchDirs();
      if (Platform.isWindows) {
        // Reads the persistent registry PATH — a real Windows dev box has a
        // non-empty PATH. Every entry is a non-empty string.
        expect(dirs, isNotEmpty);
        expect(dirs.every((d) => d.isNotEmpty), isTrue);
      } else {
        expect(
          dirs,
          posixEngineSearchDirs(
            macOS: Platform.isMacOS,
            home: Platform.environment['HOME'],
          ),
        );
        expect(dirs, contains(kNixDefaultProfileBin));
        if (Platform.isMacOS) {
          expect(dirs.take(2), <String>['/opt/homebrew/bin', '/usr/local/bin']);
        }
      }
    });

    test('repeated calls return one list, not one registry read each', () {
      // Cached for the process lifetime on every platform, so a spawn loop
      // calling this per engine pays for neither a `reg query` nor a HOME
      // read each time.
      resetEngineSearchDirsCacheForTesting();
      final first = engineSearchDirs();
      expect(identical(engineSearchDirs(), first), isTrue);
    });
  });

  group('posixEngineSearchDirs', () {
    test('macOS: Homebrew and MacPorts first, then the Nix profiles', () {
      expect(posixEngineSearchDirs(macOS: true, home: '/Users/ada'), <String>[
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/Users/ada/.nix-profile/bin',
        '/nix/var/nix/profiles/default/bin',
      ]);
    });

    test('Linux: the user profile before the system default profile', () {
      expect(posixEngineSearchDirs(macOS: false, home: '/home/ada'), <String>[
        '/home/ada/.nix-profile/bin',
        '/nix/var/nix/profiles/default/bin',
      ]);
    });

    test('no usable HOME: only the system default profile', () {
      for (final home in <String?>[
        null,
        '',
        'relative/home',
        '/',
        '/home/a:/evil',
        ' /home/ada',
        '/home/ada\x00x',
      ]) {
        expect(
          posixEngineSearchDirs(macOS: false, home: home),
          <String>[kNixDefaultProfileBin],
          reason: 'home ${home == null ? 'null' : '"$home"'}',
        );
      }
    });

    test('a trailing separator on HOME does not double it', () {
      expect(
        posixEngineSearchDirs(macOS: false, home: '/home/ada/').first,
        '/home/ada/.nix-profile/bin',
      );
    });

    test('the list cannot be modified by a caller', () {
      final dirs = posixEngineSearchDirs(macOS: false, home: '/home/ada');
      expect(() => dirs.add('/x'), throwsUnsupportedError);
    });

    test('appending them leaves an existing Nix entry where it is', () {
      final dirs = posixEngineSearchDirs(macOS: false, home: '/home/ada');
      expect(
        appendMissingPathDirs(
          '/home/ada/.nix-profile/bin:/usr/bin',
          dirs,
          separator: ':',
          caseInsensitive: false,
        ),
        '/home/ada/.nix-profile/bin:/usr/bin:'
        '/nix/var/nix/profiles/default/bin',
      );
    });
  });
}
