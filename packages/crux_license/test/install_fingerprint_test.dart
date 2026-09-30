// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The shared machine fingerprint: one file, every product on the machine,
/// adopted from wherever an earlier release kept it rather than minted fresh.
///
/// No test here touches the real home directory. Every path is resolved
/// through the `environment` map into a temp directory, and the Windows
/// layout is exercised on this host by asking for `operatingSystem:
/// 'windows'`, which only ever builds a string.
void main() {
  const macHome = <String, String>{'HOME': '/Users/u'};
  const windowsProfile = <String, String>{
    'LOCALAPPDATA': r'C:\Users\u\AppData\Local',
    'APPDATA': r'C:\Users\u\AppData\Roaming',
  };

  group('cruxLicenseDirectory', () {
    test('lives under Application Support on macOS', () {
      expect(
        cruxLicenseDirectory(environment: macHome, operatingSystem: 'macos'),
        '/Users/u/Library/Application Support/crux/license',
      );
    });

    test('lives under LOCALAPPDATA on Windows, not the roaming profile', () {
      // Roaming AppData follows the user to other computers. A machine
      // identity that roams lets two computers share one seat.
      expect(
        cruxLicenseDirectory(
          environment: windowsProfile,
          operatingSystem: 'windows',
        ),
        r'C:\Users\u\AppData\Local\crux\license',
      );
    });

    test(
      'honours XDG_DATA_HOME on Linux, and falls back to ~/.local/share',
      () {
        expect(
          cruxLicenseDirectory(
            environment: const {'HOME': '/home/u', 'XDG_DATA_HOME': '/data'},
            operatingSystem: 'linux',
          ),
          '/data/crux/license',
        );
        expect(
          cruxLicenseDirectory(
            environment: const {'HOME': '/home/u'},
            operatingSystem: 'linux',
          ),
          '/home/u/.local/share/crux/license',
        );
      },
    );

    test('throws when the variable the platform needs is unset', () {
      expect(
        () => cruxLicenseDirectory(
          environment: const {},
          operatingSystem: 'linux',
        ),
        throwsStateError,
      );
      expect(
        () => cruxLicenseDirectory(
          environment: const {'APPDATA': r'C:\Users\u\AppData\Roaming'},
          operatingSystem: 'windows',
        ),
        throwsStateError,
        reason: 'APPDATA alone is not enough; the shared directory is local',
      );
    });
  });

  group('legacyInstallFingerprintPath', () {
    test('is the per-product file, under the roaming profile on Windows', () {
      // That is where the per-product files were written, so that is where
      // they are read from — and only read.
      expect(
        legacyInstallFingerprintPath(
          'lintcrux',
          environment: windowsProfile,
          operatingSystem: 'windows',
        ),
        r'C:\Users\u\AppData\Roaming\crux\license\lintcrux.fingerprint',
      );
    });

    test('shares the base with the new directory everywhere else', () {
      expect(
        legacyInstallFingerprintPath(
          'simcrux',
          environment: macHome,
          operatingSystem: 'macos',
        ),
        '/Users/u/Library/Application Support/crux/license/simcrux.fingerprint',
      );
      expect(
        legacyInstallFingerprintPath(
          'simcrux',
          environment: const {'HOME': '/home/u', 'XDG_DATA_HOME': '/data'},
          operatingSystem: 'linux',
        ),
        '/data/crux/license/simcrux.fingerprint',
      );
    });

    test('refuses a product that is not a file-name-safe slug', () {
      for (final bad in <String>['Lint Crux', '../etc', 'LintCrux', '']) {
        expect(
          () => legacyInstallFingerprintPath(
            bad,
            environment: macHome,
            operatingSystem: 'macos',
          ),
          throwsArgumentError,
          reason: bad,
        );
        expect(
          () => InstallFingerprintFile.legacy(
            bad,
            environment: macHome,
            operatingSystem: 'macos',
          ),
          throwsArgumentError,
          reason: '$bad, at construction rather than inside a fail-soft read',
        );
      }
    });
  });

  test(
    'mintInstallFingerprint has the licence store shape: 16 bytes, base64url, '
    'unpadded, and therefore URL-safe',
    () {
      final minted = mintInstallFingerprint(Random(1));
      expect(minted, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(mintInstallFingerprint(Random(2)), isNot(minted));
      expect(
        Uri.encodeComponent(minted),
        minted,
        reason: "it goes into the path of the issuer's machine endpoints",
      );
    },
  );

  group('InstallFingerprintFile', () {
    late Directory dir;
    late File file;
    late InstallFingerprintFile store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('crux_install_fp_');
      file = File(p.join(dir.path, 'nested', 'install.fingerprint'));
      store = InstallFingerprintFile(() => file.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('.shared is install.fingerprint under the shared directory', () async {
      final shared = InstallFingerprintFile.shared(
        environment: <String, String>{'HOME': dir.path},
        operatingSystem: 'macos',
      );
      final value = await shared.readOrCreate();
      final expected = File(
        p.join(
          dir.path,
          'Library',
          'Application Support',
          'crux',
          'license',
          'install.fingerprint',
        ),
      );
      expect(expected.readAsStringSync().trim(), value);
    });

    test('.legacy reads the per-product file', () async {
      File(
          p.join(
            dir.path,
            'Library',
            'Application Support',
            'crux',
            'license',
            'lintcrux.fingerprint',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('A-t7h1HuYE4iTMMcZt-H3w\n');
      final legacy = InstallFingerprintFile.legacy(
        'lintcrux',
        environment: <String, String>{'HOME': dir.path},
        operatingSystem: 'macos',
      );
      expect(await legacy.read(), 'A-t7h1HuYE4iTMMcZt-H3w');
    });

    test('reads nothing when no file exists, and creates none', () async {
      expect(await store.read(), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('readOrCreate mints once and returns the same value after', () async {
      final first = await store.readOrCreate();
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(await store.readOrCreate(), first);
      expect(await store.read(), first);
    });

    test('a write leaves one whole file and no scratch debris', () async {
      final value = await store.readOrCreate();
      expect(file.readAsStringSync(), '$value\n');
      expect(
        file.parent.listSync().map((e) => p.basename(e.path)),
        <String>['install.fingerprint'],
        reason: 'the scratch file is renamed over the target, not left beside',
      );
    });

    test('adopt records a candidate only while nothing is recorded, and '
        'answers what the file holds', () async {
      expect(
        await store.adopt('legacy-fingerprint-0001'),
        'legacy-fingerprint-0001',
      );
      expect(
        await store.adopt('legacy-fingerprint-0002'),
        'legacy-fingerprint-0001',
        reason: 'first hit wins; the second product converges on the first',
      );
      expect(await store.read(), 'legacy-fingerprint-0001');
      expect(await store.readOrCreate(), 'legacy-fingerprint-0001');
    });

    test('adopt refuses a value that is not a fingerprint', () async {
      expect(await store.adopt('short'), isNull);
      expect(await store.adopt('has spaces in the middle of it'), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('publish records a value that read and readOrCreate then return, '
        'replacing one a headless run minted', () async {
      final minted = await store.readOrCreate();
      await store.publish('desktop-app-fingerprint-01');
      expect(await store.read(), 'desktop-app-fingerprint-01');
      expect(await store.readOrCreate(), 'desktop-app-fingerprint-01');
      expect(minted, isNot('desktop-app-fingerprint-01'));
    });

    test('a hand-edited or truncated file is no fingerprint', () async {
      file
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('short\n');
      expect(await store.read(), isNull);
      file.writeAsStringSync('has spaces in the middle of it\n');
      expect(await store.read(), isNull);
    });

    test('publish ignores a value of the wrong shape', () async {
      await store.publish('  ');
      expect(file.existsSync(), isFalse);
    });

    test('fails soft when the path cannot be resolved', () async {
      final unresolvable = InstallFingerprintFile(
        () => throw StateError('no home'),
      );
      expect(await unresolvable.read(), isNull);
      expect(await unresolvable.readOrCreate(), isNull);
      expect(await unresolvable.adopt('legacy-fingerprint-0001'), isNull);
      await unresolvable.publish('desktop-app-fingerprint-01');
    });

    test('fails soft when the file cannot be written', () async {
      // A regular file where the parent directory should be: every platform
      // refuses to create a directory there.
      final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('');
      final unwritable = InstallFingerprintFile(
        () => p.join(blocker.path, 'install.fingerprint'),
      );
      expect(await unwritable.readOrCreate(), isNull);
      expect(await unwritable.adopt('legacy-fingerprint-0001'), isNull);
      await unwritable.publish('desktop-app-fingerprint-01');
      expect(await unwritable.read(), isNull);
    });
  });

  group('SharedInstallFingerprint', () {
    late Directory dir;
    late Map<String, String> env;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('crux_shared_fp_');
      env = <String, String>{'HOME': dir.path};
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Directory licenseDir() => Directory(
      p.join(dir.path, 'Library', 'Application Support', 'crux', 'license'),
    );
    File sharedFile() => File(p.join(licenseDir().path, 'install.fingerprint'));
    SharedInstallFingerprint sourceOver() =>
        SharedInstallFingerprint(environment: env, operatingSystem: 'macos');
    Future<String?> Function() answering(String? value) =>
        () async => value;

    test('the shared file wins over every legacy source', () async {
      sharedFile()
        ..createSync(recursive: true)
        ..writeAsStringSync('shared-fingerprint-000001\n');
      final value = await sourceOver().readOrCreate(
        legacy: <Future<String?> Function()>[
          answering('legacy-fingerprint-0001'),
        ],
      );
      expect(value, 'shared-fingerprint-000001');
    });

    test('with no shared file, the first legacy source that answers is '
        'adopted, in the order given', () async {
      final asked = <String>[];
      Future<String?> Function() source(String name, String? value) =>
          () async {
            asked.add(name);
            return value;
          };
      final value = await sourceOver().readOrCreate(
        legacy: <Future<String?> Function()>[
          source('own secret', null),
          source('lintcrux file', 'legacy-fingerprint-lint1'),
          source('simcrux file', 'legacy-fingerprint-sim01'),
        ],
      );
      expect(value, 'legacy-fingerprint-lint1');
      expect(
        asked,
        <String>['own secret', 'lintcrux file'],
        reason: 'first hit wins; later sources are not consulted',
      );
      expect(
        sharedFile().readAsStringSync().trim(),
        'legacy-fingerprint-lint1',
      );
    });

    test('a legacy source that answers garbage is skipped', () async {
      final value = await sourceOver().readOrCreate(
        legacy: <Future<String?> Function()>[
          answering('short'),
          answering('legacy-fingerprint-0002'),
        ],
      );
      expect(value, 'legacy-fingerprint-0002');
    });

    test('a legacy reader that throws propagates: locked is not absent', () {
      // Minting past a credential store that is merely locked would burn the
      // seat the store was protecting. The caller already treats a locked
      // store as "try again later"; this keeps it that way.
      expect(
        sourceOver().readOrCreate(
          legacy: <Future<String?> Function()>[
            () async => throw StateError('keychain locked'),
          ],
        ),
        throwsStateError,
      );
      expect(sharedFile().existsSync(), isFalse);
    });

    test('with nothing anywhere, one is minted and recorded', () async {
      final value = await sourceOver().readOrCreate();
      expect(value, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(sharedFile().readAsStringSync().trim(), value);
      expect(await sourceOver().readOrCreate(), value);
    });

    test('the legacy files of the CLI products are read where they were '
        'written, and left there', () async {
      final legacyFile = File(
        p.join(licenseDir().path, 'simcrux.fingerprint'),
      )..createSync(recursive: true);
      await legacyFile.writeAsString('b58iPOuDuEZLXpnNKAU8jQ\n');
      final value = await sourceOver().readOrCreate(
        legacy: <Future<String?> Function()>[
          InstallFingerprintFile.legacy(
            'lintcrux',
            environment: env,
            operatingSystem: 'macos',
          ).read,
          InstallFingerprintFile.legacy(
            'simcrux',
            environment: env,
            operatingSystem: 'macos',
          ).read,
        ],
      );
      expect(value, 'b58iPOuDuEZLXpnNKAU8jQ');
      expect(
        legacyFile.readAsStringSync().trim(),
        'b58iPOuDuEZLXpnNKAU8jQ',
        reason: 'a downgrade still finds its fingerprint',
      );
    });

    test('two products racing readOrCreate over one directory end up '
        'reading the same value', () async {
      final a = sourceOver();
      final b = sourceOver();
      const fromA = 'legacy-from-product-a-1';
      const fromB = 'legacy-from-product-b-1';

      final first = await Future.wait(<Future<String?>>[
        a.readOrCreate(legacy: <Future<String?> Function()>[answering(fromA)]),
        b.readOrCreate(legacy: <Future<String?> Function()>[answering(fromB)]),
      ]);

      // Each got a real fingerprint, never a torn or absent one.
      expect(first, everyElement(anyOf(fromA, fromB)));
      // And the file holds exactly one of them, whole, with nothing beside.
      final stuck = sharedFile().readAsStringSync().trim();
      expect(stuck, anyOf(fromA, fromB));
      expect(
        licenseDir().listSync().map((e) => p.basename(e.path)),
        <String>['install.fingerprint'],
      );
      // Which is what both read from now on: the value that stuck.
      expect(await a.readOrCreate(), stuck);
      expect(await b.readOrCreate(), stuck);
    });

    test('two first runs racing with nothing to adopt converge too', () async {
      final a = sourceOver();
      final b = sourceOver();
      final minted = await Future.wait(<Future<String?>>[
        a.readOrCreate(),
        b.readOrCreate(),
      ]);
      expect(minted, everyElement(matches(RegExp(r'^[A-Za-z0-9_-]{22}$'))));
      final stuck = sharedFile().readAsStringSync().trim();
      expect(minted, contains(stuck));
      expect(await a.readOrCreate(), stuck);
      expect(await b.readOrCreate(), stuck);
    });

    test('a directory that cannot be created answers null', () async {
      final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('');
      final broken = SharedInstallFingerprint(
        environment: <String, String>{'HOME': blocker.path},
        operatingSystem: 'macos',
      );
      expect(await broken.readOrCreate(), isNull);
      expect(
        await broken.readOrCreate(
          legacy: <Future<String?> Function()>[
            answering('legacy-fingerprint-0001'),
          ],
        ),
        isNull,
        reason: 'a legacy value cannot be kept either; the caller falls back',
      );
    });

    test(
      'a missing home directory answers null rather than throwing',
      () async {
        final homeless = SharedInstallFingerprint(
          environment: const <String, String>{},
          operatingSystem: 'macos',
        );
        expect(await homeless.readOrCreate(), isNull);
      },
    );

    test('takes an explicit file when given one', () async {
      final file = File(p.join(dir.path, 'elsewhere', 'install.fingerprint'));
      final source = SharedInstallFingerprint(
        file: InstallFingerprintFile(() => file.path),
      );
      final value = await source.readOrCreate();
      expect(file.readAsStringSync().trim(), value);
    });
  });

  group('InMemoryInstallFingerprintSource', () {
    test('holds a value and answers it', () async {
      final source = InMemoryInstallFingerprintSource(
        value: 'fingerprint-1234',
      );
      expect(
        await source.readOrCreate(
          legacy: <Future<String?> Function()>[() async => 'legacy-fp-00001'],
        ),
        'fingerprint-1234',
      );
    });

    test(
      'adopts the first legacy value of the right shape, in order',
      () async {
        final source = InMemoryInstallFingerprintSource();
        expect(
          await source.readOrCreate(
            legacy: <Future<String?> Function()>[
              () async => null,
              () async => 'short',
              () async => 'legacy-fingerprint-0003',
              () async => 'legacy-fingerprint-0004',
            ],
          ),
          'legacy-fingerprint-0003',
        );
        expect(source.value, 'legacy-fingerprint-0003');
        expect(await source.readOrCreate(), 'legacy-fingerprint-0003');
      },
    );

    test('mints when it has nothing, once', () async {
      final source = InMemoryInstallFingerprintSource();
      final minted = await source.readOrCreate();
      expect(minted, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(await source.readOrCreate(), minted);
    });

    test('an unusable source answers null, whatever it is offered', () async {
      final source = InMemoryInstallFingerprintSource(usable: false);
      expect(await source.readOrCreate(), isNull);
      expect(
        await source.readOrCreate(
          legacy: <Future<String?> Function()>[
            () async => 'legacy-fingerprint-0001',
          ],
        ),
        isNull,
      );
      expect(source.value, isNull);
    });
  });
}
