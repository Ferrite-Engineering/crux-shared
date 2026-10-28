// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/license_fixtures.dart';

/// The file a licence is kept in when the operating system's credential
/// store is unavailable: where it lives, that only its owner can read it from
/// the moment it exists, and which credentials may go there at all.
void main() {
  late Directory home;
  late Map<String, String> environment;

  setUp(() {
    home = Directory.systemTemp.createTempSync('crux_license_fallback_');
    environment = <String, String>{
      'HOME': home.path,
      'XDG_DATA_HOME': p.join(home.path, 'data'),
      'LOCALAPPDATA': home.path,
      'APPDATA': home.path,
    };
  });
  tearDown(() => home.deleteSync(recursive: true));

  LicenseFallbackFile fileFor(String product) =>
      LicenseFallbackFile.forProduct(product, environment: environment);

  /// The permission bits of [path].
  int modeOf(String path) => File(path).statSync().mode & 0x1ff;

  group('where it lives', () {
    test('per product, beside the shared install fingerprint', () {
      for (final os in <String>['linux', 'macos', 'windows']) {
        final path = licenseFallbackFilePath(
          'netcrux',
          environment: environment,
          operatingSystem: os,
        );
        final context = os == 'windows' ? p.windows : p.posix;
        expect(
          context.dirname(path),
          cruxLicenseDirectory(environment: environment, operatingSystem: os),
          reason: os,
        );
        expect(context.basename(path), 'netcrux.license', reason: os);
      }
    });

    test('a product slug that is not a file name is refused', () {
      expect(
        () => licenseFallbackFilePath('../net', environment: environment),
        throwsArgumentError,
      );
    });

    test('no home directory reads as no file and refuses a write', () async {
      final file = LicenseFallbackFile.forProduct(
        'netcrux',
        environment: const <String, String>{},
        operatingSystem: 'linux',
      );
      expect(file.path, isNull);
      expect(file.exists(), isFalse);
      expect(await file.read(), isNull);
      expect(await file.delete(), isFalse, reason: 'nothing can be there');
      await expectLater(file.write('x'), throwsStateError);
    });
  });

  group('owner-only', () {
    test('the file is created 0600, and stays 0600 when replaced', () async {
      final file = fileFor('netcrux');
      await file.write('{"credential":"one"}');

      expect(modeOf(file.path!), 0x180, reason: 'rw------- on creation');
      expect(await file.read(), '{"credential":"one"}');

      await file.write('{"credential":"two"}');
      expect(modeOf(file.path!), 0x180, reason: 'and after a replace');
      expect(await file.read(), '{"credential":"two"}');
    }, skip: Platform.isWindows ? 'Windows has ACLs, not modes' : false);

    test(
      'a file planted with a wider mode is replaced by an owner-only one',
      () async {
        final file = fileFor('netcrux');
        File(file.path!)
          ..createSync(recursive: true)
          ..writeAsStringSync('planted');
        Process.runSync('chmod', <String>['644', file.path!]);
        expect(modeOf(file.path!), 0x1a4);

        await file.write('{"credential":"mine"}');

        expect(modeOf(file.path!), 0x180);
        expect(await file.read(), '{"credential":"mine"}');
      },
      skip: Platform.isWindows ? 'Windows has ACLs, not modes' : false,
    );

    test('no scratch file is left behind', () async {
      final file = fileFor('netcrux');
      await file.write('a');
      await file.write('b');

      final names = Directory(
        p.dirname(file.path!),
      ).listSync().map((e) => p.basename(e.path)).toList();
      expect(names, <String>['netcrux.license']);
    });
  });

  group('delete', () {
    test('removes the file and says whether there was one', () async {
      final file = fileFor('netcrux');
      expect(await file.delete(), isFalse);

      await file.write('x');
      expect(file.exists(), isTrue);
      expect(await file.delete(), isTrue);

      expect(file.exists(), isFalse);
      expect(await file.read(), isNull);
    });

    test('products do not share a file', () async {
      await fileFor('netcrux').write('net');
      await fileFor('wavecrux').write('wave');

      await fileFor('netcrux').delete();

      expect(await fileFor('wavecrux').read(), 'wave');
    });
  });

  group('which credentials may use it', () {
    late TestIssuerKeys issuer;
    setUpAll(() async => issuer = await TestIssuerKeys.fromSeed(7));

    test('a licence file and a machine file may', () async {
      expect(
        licenseCredentialMayUseFallbackFile(
          await issuer.mintFile(filePayload()),
        ),
        isTrue,
      );
      expect(
        licenseCredentialMayUseFallbackFile(
          await issuer.mintMachineFile(machineFilePayload()),
        ),
        isTrue,
      );
    });

    test('a licence key never may', () async {
      expect(
        licenseCredentialMayUseFallbackFile(await issuer.mintKey(keyPayload())),
        isFalse,
      );
    });

    test('text that is no credential may not', () {
      expect(licenseCredentialMayUseFallbackFile(''), isFalse);
      expect(licenseCredentialMayUseFallbackFile('hunter2'), isFalse);
      expect(
        licenseCredentialMayUseFallbackFile(
          '-----BEGIN LICENSE FILE-----\nnot base64\n'
          '-----END LICENSE FILE-----',
        ),
        isFalse,
      );
    });
  });
}
