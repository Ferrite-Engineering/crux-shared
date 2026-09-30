// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Windows `CreateProcess` searches the *calling* process's current directory
// before the system directories and PATH. No product moves its own current
// directory, so a developer who launched one from a terminal inside a
// repository hands a `verilator.exe` or `code.exe` committed to that
// repository priority over the real one. Resolving to an absolute path
// before the spawn is what closes it.
//
// These run on the macOS and Linux machines CI uses: `windows: true` plus
// the injected `exists` probe make the Windows branch host-independent, so
// the guard does not wait for a Windows runner.
//
// MUTATION: making `resolveSpawnExecutable` answer the bare name on Windows
// turns the first group red.

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_io/src/spawn_environment.dart';
import 'package:test/test.dart';

void main() {
  const path =
      r'C:\rtl-repo;C:\tools\oss-cad-suite\bin;'
      r'C:\Program Files\Microsoft VS Code\bin;C:\Windows';

  String resolve(
    String exe, {
    required Set<String> present,
    String? pathEnvironment = path,
    String? pathExt,
  }) {
    return resolveSpawnExecutable(
      exe,
      pathEnvironment: pathEnvironment,
      windows: true,
      pathExt: pathExt,
      exists: present.contains,
    );
  }

  group('resolveSpawnExecutable on Windows', () {
    test('a bare engine name resolves to the absolute PATH hit', () {
      expect(
        resolve(
          'verible-verilog-lint',
          present: <String>{
            r'C:\tools\oss-cad-suite\bin\verible-verilog-lint.EXE',
          },
        ),
        r'C:\tools\oss-cad-suite\bin\verible-verilog-lint.EXE',
      );
    });

    test('a bare editor name resolves to the absolute PATH hit', () {
      expect(
        resolve(
          'code',
          present: <String>{r'C:\Program Files\Microsoft VS Code\bin\code.CMD'},
        ),
        r'C:\Program Files\Microsoft VS Code\bin\code.CMD',
      );
    });

    // The defect itself: the planted copy sits in the project directory,
    // which is the launching shell's current directory and need not be on
    // PATH at all. Once the spawn is handed an absolute path, CreateProcess
    // never searches that directory, so the plant cannot win.
    test('a planted binary in the launch directory cannot displace PATH', () {
      final resolved = resolve(
        'verilator',
        // `C:\rtl-repo` is the project and the launching shell's current
        // directory. It appears FIRST in this fixture's PATH only to prove
        // the resolver answers with a concrete file rather than a name.
        present: <String>{r'C:\tools\oss-cad-suite\bin\verilator.EXE'},
      );
      expect(resolved, r'C:\tools\oss-cad-suite\bin\verilator.EXE');
      expect(resolved.contains('rtl-repo'), isFalse);
    });

    test('the first PATH directory holding a match wins', () {
      expect(
        resolve(
          'explorer',
          present: <String>{
            r'C:\tools\oss-cad-suite\bin\explorer.EXE',
            r'C:\Windows\explorer.EXE',
          },
        ),
        r'C:\tools\oss-cad-suite\bin\explorer.EXE',
      );
    });

    test('PATHEXT order decides which extension wins', () {
      expect(
        resolve(
          'svlint',
          present: <String>{
            r'C:\tools\oss-cad-suite\bin\svlint.BAT',
            r'C:\tools\oss-cad-suite\bin\svlint.EXE',
          },
          pathExt: '.COM;.EXE;.BAT;.CMD',
        ),
        r'C:\tools\oss-cad-suite\bin\svlint.EXE',
      );
      expect(
        resolve(
          'svlint',
          present: <String>{
            r'C:\tools\oss-cad-suite\bin\svlint.BAT',
            r'C:\tools\oss-cad-suite\bin\svlint.EXE',
          },
          pathExt: '.BAT;.EXE',
        ),
        r'C:\tools\oss-cad-suite\bin\svlint.BAT',
      );
    });

    test('an empty PATHEXT falls back to the Windows default list', () {
      expect(
        resolve(
          'slang',
          present: <String>{r'C:\tools\oss-cad-suite\bin\slang.EXE'},
          pathExt: ' ',
        ),
        r'C:\tools\oss-cad-suite\bin\slang.EXE',
      );
      expect(kDefaultWindowsPathExt, '.COM;.EXE;.BAT;.CMD');
    });

    test('a name that already carries an extension is tried verbatim', () {
      expect(
        resolve(
          'ghdl.exe',
          present: <String>{r'C:\tools\oss-cad-suite\bin\ghdl.exe'},
        ),
        r'C:\tools\oss-cad-suite\bin\ghdl.exe',
      );
    });

    test('an explicit path is never rewritten', () {
      const custom = r'D:\custom\verible-verilog-lint.exe';
      expect(resolve(custom, present: <String>{custom}), custom);
      expect(resolve('bin/slang', present: const <String>{}), 'bin/slang');
      expect(resolve(r'bin\slang', present: const <String>{}), r'bin\slang');
      expect(resolve('C:slang', present: const <String>{}), 'C:slang');
    });

    test('an unresolvable name is left bare so the spawn fails loudly', () {
      // Better a ProcessException the caller reports as "not installed"
      // than a silent fallback to whatever the launch directory holds.
      expect(resolve('slang', present: const <String>{}), 'slang');
    });

    test('an empty name or an empty or absent PATH resolves nothing', () {
      expect(resolve('', present: const <String>{''}), '');
      expect(
        resolve('slang', present: const <String>{}, pathEnvironment: null),
        'slang',
      );
      expect(
        resolve('slang', present: const <String>{}, pathEnvironment: ''),
        'slang',
      );
      expect(
        resolve('slang', present: const <String>{}, pathEnvironment: ' ; ;'),
        'slang',
      );
    });

    test('a trailing separator on a PATH entry does not double up', () {
      expect(
        resolveSpawnExecutable(
          'verilator',
          pathEnvironment: r'C:\tools\bin\',
          windows: true,
          exists: <String>{r'C:\tools\bin\verilator.EXE'}.contains,
        ),
        r'C:\tools\bin\verilator.EXE',
      );
      expect(
        resolveSpawnExecutable(
          'verilator',
          pathEnvironment: 'C:/tools/bin/',
          windows: true,
          exists: <String>{r'C:/tools/bin\verilator.EXE'}.contains,
        ),
        r'C:/tools/bin\verilator.EXE',
      );
    });
  });

  test('POSIX is left alone: execvp never consults the current directory', () {
    expect(
      resolveSpawnExecutable(
        'verilator',
        pathEnvironment: '/opt/homebrew/bin:/usr/bin',
        windows: false,
        exists: (_) => true,
      ),
      'verilator',
    );
  });

  // The host form every real spawn site calls. On a macOS or Linux run it
  // must be the identity, whatever the environment says, or it would be
  // asserting the host's PATH contents rather than the resolver.
  test('resolveSpawnExecutableForHost is the identity off Windows', () {
    expect(resolveSpawnExecutableForHost('open'), 'open');
    expect(resolveSpawnExecutableForHost('xdg-open'), 'xdg-open');
    expect(
      resolveSpawnExecutableForHost(
        'yosys',
        environment: const <String, String>{'PATH': '/opt/oss-cad/bin'},
      ),
      'yosys',
    );
  }, testOn: '!windows');

  group('spawnEnvironmentValue', () {
    test('finds the Windows `Path` spelling case-insensitively', () {
      const env = <String, String>{'Path': r'C:\Windows', 'PathExt': '.EXE'};
      expect(spawnEnvironmentValue(env, 'PATH', windows: true), r'C:\Windows');
      expect(spawnEnvironmentValue(env, 'PATHEXT', windows: true), '.EXE');
    });

    test('prefers the exact spelling when both are present', () {
      const env = <String, String>{'Path': 'mixed', 'PATH': 'exact'};
      expect(spawnEnvironmentValue(env, 'PATH', windows: true), 'exact');
    });

    test('is case-sensitive on POSIX', () {
      const env = <String, String>{'Path': '/usr/bin'};
      expect(spawnEnvironmentValue(env, 'PATH', windows: false), isNull);
    });

    test('answers null for a variable that is not set', () {
      expect(
        spawnEnvironmentValue(const <String, String>{}, 'PATH', windows: true),
        isNull,
      );
    });
  });

  // The case resolution alone leaves open: a tool that is not installed.
  // Handed on bare, CreateProcess would search the launching directory for
  // it, so a planted binary would run for exactly the users without the real
  // one. The strict form throws what a missing binary throws instead.
  //
  // MUTATION: returning the bare name from `requireSpawnExecutable` (or
  // throwing anything but a ProcessException) turns this group red.
  group('requireSpawnExecutable on Windows', () {
    String require(String exe, {required Set<String> present}) =>
        requireSpawnExecutable(
          exe,
          pathEnvironment: path,
          windows: true,
          exists: present.contains,
        );

    test('an installed tool resolves exactly as the lenient form does', () {
      const present = <String>{r'C:\tools\oss-cad-suite\bin\verilator.EXE'};
      expect(
        require('verilator', present: present),
        r'C:\tools\oss-cad-suite\bin\verilator.EXE',
      );
      expect(
        require('verilator', present: present),
        resolve('verilator', present: present),
      );
    });

    test('a tool nothing on PATH answers to throws instead of going bare', () {
      expect(
        () => require('verilator', present: const <String>{}),
        throwsA(
          isA<ProcessException>()
              .having((e) => e.executable, 'executable', 'verilator')
              .having((e) => e.arguments, 'arguments', isEmpty)
              .having((e) => e.message, 'message', 'not found on PATH')
              .having((e) => e.errorCode, 'errorCode', 2),
        ),
      );
    });

    test('an empty name throws too: there is nothing to start', () {
      expect(
        () => require('', present: const <String>{''}),
        throwsA(isA<ProcessException>()),
      );
    });

    test('an explicit path is returned unchanged, found or not', () {
      // The caller named a file; CreateProcess will not search for it, and
      // a missing one fails in the spawn as it always has.
      const custom = r'D:\custom\verilator.exe';
      expect(require(custom, present: const <String>{}), custom);
      expect(require('bin/slang', present: const <String>{}), 'bin/slang');
      expect(require('C:slang', present: const <String>{}), 'C:slang');
    });
  });

  test('requireSpawnExecutable is the identity off Windows', () {
    // execvp never searches the current directory, and a missing binary
    // already fails in the spawn with the OS's own ProcessException.
    expect(
      requireSpawnExecutable(
        'verilator',
        pathEnvironment: '/usr/bin',
        windows: false,
        exists: (_) => false,
      ),
      'verilator',
    );
  });

  group('SpawnHost', () {
    const host = SpawnHost(
      windows: true,
      environment: <String, String>{
        'Path': r'C:\Windows\System32;C:\tools\bin',
        'PATHEXT': '.EXE',
      },
      exists: _presentOnHost,
    );

    test('resolves against its own Path, case-insensitively', () {
      expect(host.resolveExecutable('reg'), r'C:\Windows\System32\reg.EXE');
      expect(host.requireExecutable('reg'), r'C:\Windows\System32\reg.EXE');
    });

    test('searches the child environment first when one is given', () {
      const child = <String, String>{'PATH': r'C:\augmented'};
      expect(
        host.requireExecutable('yosys', childEnvironment: child),
        r'C:\augmented\yosys.EXE',
      );
      // Without it, the same name is not on the host's own Path.
      expect(host.resolveExecutable('yosys'), 'yosys');
    });

    test('a child environment without PATH falls back to the host', () {
      const child = <String, String>{'NO_COLOR': '1'};
      expect(
        host.requireExecutable('reg', childEnvironment: child),
        r'C:\Windows\System32\reg.EXE',
      );
    });

    test('require throws where resolve would hand back a bare name', () {
      expect(host.resolveExecutable('explorer'), 'explorer');
      expect(
        () => host.requireExecutable('explorer'),
        throwsA(isA<ProcessException>()),
      );
    });

    test('a POSIX host leaves every name alone', () {
      const posix = SpawnHost(windows: false, exists: _presentOnHost);
      expect(posix.requireExecutable('reg'), 'reg');
      expect(posix.resolveExecutable('explorer'), 'explorer');
    });

    test('current() reflects the live process', () {
      final live = SpawnHost.current();
      expect(live.windows, Platform.isWindows);
      expect(live.exists, isNull);
    });
  });

  test('requireSpawnExecutableForHost is the identity off Windows', () {
    expect(requireSpawnExecutableForHost('df'), 'df');
    expect(
      requireSpawnExecutableForHost(
        'crux-no-such-tool',
        environment: const <String, String>{'PATH': '/nowhere'},
      ),
      'crux-no-such-tool',
    );
  }, testOn: '!windows');

  group('isAbsoluteSpawnPath', () {
    test('accepts the absolute forms an editor cannot read as an option', () {
      expect(isAbsoluteSpawnPath('/rtl/cpu.v'), isTrue);
      expect(isAbsoluteSpawnPath(r'C:\rtl\cpu.v'), isTrue);
      expect(isAbsoluteSpawnPath('C:/rtl/cpu.v'), isTrue);
      expect(isAbsoluteSpawnPath(r'\\build\rtl\cpu.v'), isTrue);
      expect(isAbsoluteSpawnPath('//build/rtl/cpu.v'), isTrue);
    });

    test('refuses the payload a drive-letter guess would admit', () {
      // `file.length >= 2 && file[1] == ":"` answers true for every one of
      // these, which is why it is not an absoluteness test.
      expect(isAbsoluteSpawnPath('+:!curl x|sh'), isFalse);
      expect(isAbsoluteSpawnPath('Z:+!curl x|sh'), isFalse);
      expect(isAbsoluteSpawnPath('-:--remote-send'), isFalse);
      expect(isAbsoluteSpawnPath('C:rtl'), isFalse);
    });

    test('refuses relative, option-shaped, empty and NUL-bearing paths', () {
      expect(isAbsoluteSpawnPath('rtl/cpu.v'), isFalse);
      expect(isAbsoluteSpawnPath('../../../etc/shadow'), isFalse);
      expect(isAbsoluteSpawnPath('-c'), isFalse);
      expect(isAbsoluteSpawnPath(''), isFalse);
      expect(isAbsoluteSpawnPath('/rtl/cpu.v\u0000-evil'), isFalse);
    });
  });
}

/// The files a [SpawnHost] test lays out: `reg` in System32, and `yosys`
/// only on an augmented directory the host's own `Path` does not name.
bool _presentOnHost(String path) => const <String>{
  r'C:\Windows\System32\reg.EXE',
  r'C:\augmented\yosys.EXE',
}.contains(path);
