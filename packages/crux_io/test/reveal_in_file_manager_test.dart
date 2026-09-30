// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Every branch of the reveal runs here, on whatever host CI uses, through the
// injected operating system, environment, probe and runner. Nothing is
// spawned.
//
// The Windows branch is the one that matters: Explorer is spawned by name,
// and on Windows a bare name is searched for in the launching process's
// current directory before the system directories and PATH. A product
// launched from a terminal inside a repository would run an `explorer.exe`
// committed there.
//
// MUTATION: spawning the bare `explorer` (skipping the resolution) turns the
// first Windows test red; resolving with the lenient form, which hands back a
// bare name when nothing on PATH answers, turns "spawns nothing" red;
// splitting `/select,` from the path turns the argument test red.

import 'package:crux_io/crux_io.dart';
import 'package:test/test.dart';

/// One command the reveal asked to run.
typedef _Command = ({String executable, List<String> arguments});

void main() {
  late List<_Command> commands;

  /// A runner that records each command and answers [exitCodes] in order
  /// (0 once they run out).
  RevealCommandRunner recording([List<int> exitCodes = const <int>[]]) {
    final codes = List<int>.of(exitCodes);
    return (executable, arguments) async {
      commands.add((executable: executable, arguments: arguments));
      return codes.isEmpty ? 0 : codes.removeAt(0);
    };
  }

  setUp(() => commands = <_Command>[]);

  group('on Windows', () {
    const env = <String, String>{
      'Path': r'C:\rtl-repo;C:\Windows\System32;C:\Windows',
      'PATHEXT': '.COM;.EXE;.BAT;.CMD',
    };
    const file = r'C:\rtl-repo\sim\wave.vcd';

    test('spawns Explorer by absolute path, never by bare name', () async {
      final revealed = await revealInFileManager(
        file,
        operatingSystem: 'windows',
        environment: env,
        exists: <String>{r'C:\Windows\explorer.EXE'}.contains,
        runCommand: recording(),
      );

      expect(revealed, isTrue);
      expect(commands, hasLength(1));
      expect(commands.single.executable, r'C:\Windows\explorer.EXE');
      expect(
        commands.single.executable.contains('rtl-repo'),
        isFalse,
        reason: 'the launch directory is the repository; nothing from it runs',
      );
    });

    test('passes `/select,` and the path as one argument', () async {
      await revealInFileManager(
        file,
        operatingSystem: 'windows',
        environment: env,
        exists: <String>{r'C:\Windows\explorer.EXE'}.contains,
        runCommand: recording(),
      );

      // Split in two, Explorer ignores the switch and opens the folder with
      // nothing selected.
      expect(commands.single.arguments, <String>['/select,$file']);
    });

    test('spawns nothing when no PATH directory holds Explorer', () async {
      // A bare `explorer` handed to CreateProcess would be searched for in
      // the launching directory first, which is the one place a reveal must
      // never run a binary from.
      final revealed = await revealInFileManager(
        file,
        operatingSystem: 'windows',
        environment: env,
        exists: (_) => false,
        runCommand: recording(),
      );

      expect(revealed, isFalse);
      expect(commands, isEmpty);
    });

    test('reads the search path from a lower-case `Path` key', () async {
      await revealInFileManager(
        file,
        operatingSystem: 'windows',
        environment: const <String, String>{'path': r'C:\Windows'},
        exists: <String>{r'C:\Windows\explorer.EXE'}.contains,
        runCommand: recording(),
      );

      expect(commands.single.executable, r'C:\Windows\explorer.EXE');
    });
  });

  group('on macOS', () {
    test('asks Finder to select the file', () async {
      final revealed = await revealInFileManager(
        '/Users/me/rtl/wave.vcd',
        operatingSystem: 'macos',
        environment: const <String, String>{'PATH': '/usr/bin:/bin'},
        exists: (_) => true,
        runCommand: recording(),
      );

      expect(revealed, isTrue);
      // execvp searches PATH only, so off Windows the name is spawned as is.
      expect(commands.single.executable, 'open');
      expect(commands.single.arguments, <String>[
        '-R',
        '/Users/me/rtl/wave.vcd',
      ]);
    });
  });

  group('on Linux', () {
    const file = '/home/me/rtl/wave.vcd';

    test('selects the file through the FileManager1 D-Bus interface', () async {
      final revealed = await revealInFileManager(
        file,
        operatingSystem: 'linux',
        environment: const <String, String>{'PATH': '/usr/bin'},
        runCommand: recording(),
      );

      expect(revealed, isTrue);
      expect(commands, hasLength(1));
      expect(commands.single.executable, 'dbus-send');
      expect(
        commands.single.arguments,
        contains('array:string:file://$file'),
      );
    });

    // ShowItems takes URIs. Pasted in raw, a space ends nothing but a `#`
    // starts a fragment and a `%` starts an escape, so the file manager is
    // asked for a different file, or none. Percent-encoded, each survives.
    //
    // MUTATION: building the URI as 'file://$filePath' turns this red.
    test('passes the file as a percent-encoded file URI', () async {
      await revealInFileManager(
        '/home/me/rtl/my wave #2 100%.vcd',
        operatingSystem: 'linux',
        environment: const <String, String>{'PATH': '/usr/bin'},
        runCommand: recording(),
      );

      expect(
        commands.single.arguments,
        contains(
          'array:string:file:///home/me/rtl/my%20wave%20%232%20100%25.vcd',
        ),
      );
    });

    test('falls back to opening the folder when D-Bus refuses', () async {
      final revealed = await revealInFileManager(
        file,
        operatingSystem: 'linux',
        environment: const <String, String>{'PATH': '/usr/bin'},
        runCommand: recording(<int>[1]),
      );

      expect(revealed, isTrue);
      expect(commands.map((c) => c.executable), <String>[
        'dbus-send',
        'xdg-open',
      ]);
      expect(commands.last.arguments, <String>['/home/me/rtl']);
    });
  });

  test('an unsupported platform reveals nothing', () async {
    final revealed = await revealInFileManager(
      '/tmp/wave.vcd',
      operatingSystem: 'fuchsia',
      environment: const <String, String>{},
      runCommand: recording(),
    );

    expect(revealed, isFalse);
    expect(commands, isEmpty);
  });

  test('a spawn that throws is swallowed and reported as false', () async {
    final revealed = await revealInFileManager(
      '/Users/me/rtl/wave.vcd',
      operatingSystem: 'macos',
      environment: const <String, String>{},
      runCommand: (_, _) async => throw const FormatException('no finder'),
    );

    expect(revealed, isFalse);
  });
}
