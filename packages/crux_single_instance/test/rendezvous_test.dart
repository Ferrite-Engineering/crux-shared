// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_single_instance/src/file_mode.dart';
import 'package:crux_single_instance/src/protocol.dart';
import 'package:crux_single_instance/src/rendezvous.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('csi'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group(
    'resolveSingleInstanceDirectory on a POSIX host',
    () {
      test('uses a private runtime directory', () {
        final runtime = Directory(p.join(tmp.path, 'run'))..createSync();
        setPosixFileMode(runtime.path, 0x1C0);

        final dir = resolveSingleInstanceDirectory(
          environment: {'XDG_RUNTIME_DIR': runtime.path, 'HOME': tmp.path},
          isWindows: false,
        );

        expect(dir, p.join(runtime.path, kSingleInstanceDirectoryName));
        expect(isPrivateDirectory(dir!), isTrue);
      });

      test('passes over a runtime directory others can enter', () {
        final runtime = Directory(p.join(tmp.path, 'run'))..createSync();
        setPosixFileMode(runtime.path, 0x1ED); // 0o755

        final dir = resolveSingleInstanceDirectory(
          environment: {'XDG_RUNTIME_DIR': runtime.path, 'HOME': tmp.path},
          isWindows: false,
        );

        expect(
          dir,
          p.join(tmp.path, '.cache', kSingleInstanceDirectoryName),
        );
        expect(isPrivateDirectory(dir!), isTrue);
      });

      test('prefers XDG_CACHE_HOME to ~/.cache', () {
        final cache = p.join(tmp.path, 'cache');

        final dir = resolveSingleInstanceDirectory(
          environment: {'XDG_CACHE_HOME': cache, 'HOME': tmp.path},
          isWindows: false,
        );

        expect(dir, p.join(cache, kSingleInstanceDirectoryName));
      });

      test('a relative runtime directory is ignored', () {
        final dir = resolveSingleInstanceDirectory(
          environment: {'XDG_RUNTIME_DIR': 'run', 'HOME': tmp.path},
          isWindows: false,
        );

        expect(dir, p.join(tmp.path, '.cache', kSingleInstanceDirectoryName));
      });

      test('no runtime directory and no home is none', () {
        expect(
          resolveSingleInstanceDirectory(environment: {}, isWindows: false),
          isNull,
        );
      });

      test('an override is made private too', () {
        final override = p.join(tmp.path, 'mine');
        Directory(override).createSync();
        setPosixFileMode(override, 0x1FF); // 0o777

        final dir = resolveSingleInstanceDirectory(
          environment: const {},
          isWindows: false,
          override: override,
        );

        expect(dir, override);
        expect(FileStat.statSync(override).mode & 0x1FF, 0x1C0);
      });

      test('an override that cannot be created is none', () {
        final file = File(p.join(tmp.path, 'file'))..writeAsStringSync('x');

        expect(
          resolveSingleInstanceDirectory(
            environment: const {},
            isWindows: false,
            override: p.join(file.path, 'below'),
          ),
          isNull,
        );
      });
    },
    skip: Platform.isWindows ? 'POSIX modes' : false,
  );

  test('Windows needs LOCALAPPDATA', () {
    expect(
      resolveSingleInstanceDirectory(environment: const {}, isWindows: true),
      isNull,
    );
    expect(
      resolveSingleInstanceDirectory(
        environment: const {'LOCALAPPDATA': 'relative'},
        isWindows: true,
      ),
      isNull,
    );
  });

  group('SingleInstanceAdvert', () {
    String path() => p.join(tmp.path, 'advert.json');

    test('round-trips', () {
      final token = generateSingleInstanceSecret();
      SingleInstanceAdvert(token: token, port: 4242).write(path());

      final read = SingleInstanceAdvert.read(path())!;

      expect(read.token, token);
      expect(read.port, 4242);
      expect(File('${path()}.$pid.tmp').existsSync(), isFalse);
    });

    test(
      'is readable by its owner only',
      () {
        SingleInstanceAdvert(
          token: generateSingleInstanceSecret(),
        ).write(path());

        expect(FileStat.statSync(path()).mode & 0x1FF, 0x180);
      },
      skip: Platform.isWindows ? 'POSIX modes' : false,
    );

    final invalid = <String, String>{
      'not JSON': '{',
      'not an object': '[]',
      'another protocol': '{"protocol":"x","token":"${'a' * 32}"}',
      'a short token': '{"protocol":"$kSingleInstanceProtocol","token":"abc"}',
      'a port out of range':
          '{"protocol":"$kSingleInstanceProtocol","token":"${'a' * 32}",'
          '"port":70000}',
      'a port that is not a number':
          '{"protocol":"$kSingleInstanceProtocol","token":"${'a' * 32}",'
          '"port":"80"}',
      'too large': ' ' * 2000,
    };
    for (final MapEntry(key: name, value: text) in invalid.entries) {
      test('refuses $name', () {
        File(path()).writeAsStringSync(text);
        expect(SingleInstanceAdvert.read(path()), isNull);
      });
    }

    test('an absent advert reads as none', () {
      expect(SingleInstanceAdvert.read(path()), isNull);
    });
  });

  group('protocol', () {
    test('secrets are 128 random bits in hex', () {
      final a = generateSingleInstanceSecret();
      expect(isSingleInstanceSecret(a), isTrue);
      expect(a, isNot(generateSingleInstanceSecret()));
    });

    test('the two proofs differ, and the client proof binds the link', () {
      const token = 'token';
      final server = singleInstanceServerProof(
        token: token,
        clientNonce: 'c',
        serverNonce: 's',
      );
      final client = singleInstanceClientProof(
        token: token,
        clientNonce: 'c',
        serverNonce: 's',
        link: 'viewer://a',
      );
      expect(isSingleInstanceProof(server), isTrue);
      expect(isSingleInstanceProof(client), isTrue);
      expect(server, isNot(client));
      expect(
        client,
        isNot(
          singleInstanceClientProof(
            token: token,
            clientNonce: 'c',
            serverNonce: 's',
            link: 'viewer://b',
          ),
        ),
      );
    });

    test('comparison is exact', () {
      expect(singleInstanceConstantTimeEquals('abc', 'abc'), isTrue);
      expect(singleInstanceConstantTimeEquals('abc', 'abd'), isFalse);
      expect(singleInstanceConstantTimeEquals('abc', 'abcd'), isFalse);
      expect(singleInstanceConstantTimeEquals('', ''), isTrue);
    });
  });
}
