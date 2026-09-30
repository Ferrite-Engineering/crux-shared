// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_policy/crux_policy.dart';
import 'package:crux_policy/src/policy_inspect.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/ed25519_sign.dart';

/// `crux-policy inspect --key` must answer what a product on this machine
/// would do with the file WHERE IT IS. Verifying every file as though it had
/// arrived through `CRUX_POLICY` was wrong in both directions: it refused an
/// unsigned file the machine honours, and verified clean against a key file
/// the machine ignores.
///
/// Driven through [inspectionLoader] with the well-known location redirected
/// into a temporary directory, because the real one needs administrator
/// rights to write — which is the property being tested.
void main() {
  late Directory dir;
  late TestEd25519KeyPair org;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crux_policy_inspect_');
    org = TestEd25519KeyPair.fromSeed(List<int>.filled(32, 9));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final policy = <String, Object?>{
    'schema': 1,
    'org': 'Example Semiconductor',
    'suite': <String, Object?>{'telemetry': 'deny'},
  };

  String wellKnown() => p.join(dir.path, '.crux-policy.json');

  String write(String path, Map<String, Object?> body) {
    File(path).writeAsStringSync(jsonEncode(body));
    return path;
  }

  Map<String, Object?> signed(Map<String, Object?> body) => <String, Object?>{
    ...body,
    'signature': base64.encode(
      org.sign(utf8.encode(PolicyLoader.canonicalPayload(body))),
    ),
  };

  String installKey() {
    final path = p.join(dir.path, kPolicyPublicKeyFileName);
    File(path).writeAsStringSync(base64.encode(org.publicKey));
    return path;
  }

  PolicyLoadResult inspect(String policyPath, {String? keyPath}) =>
      inspectionLoader(
        policyPath: policyPath,
        suppliedKey: org.publicKey,
        suppliedKeyPath: keyPath,
        wellKnownPath: wellKnown(),
      ).load();

  Future<void> chmod(String mode, String path) async {
    final r = await Process.run('chmod', [mode, path]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
  }

  final posix = !Platform.isWindows;

  group('the file is judged by the route that reaches it', () {
    test('an unsigned file AT the well-known path is honoured', () {
      // The machine honours it — the location needs administrator rights to
      // write. Reporting it refused sent administrators chasing a signature
      // problem that did not exist.
      final result = inspect(write(wellKnown(), policy));
      expect(result.wasLoaded, isTrue, reason: result.detail);
      expect(result.signed, isFalse);
      expect(result.discovery, PolicyDiscovery.wellKnownPath);
    });

    test('an unsigned file anywhere else is refused, as CRUX_POLICY is', () {
      final elsewhere = write(p.join(dir.path, 'share.json'), policy);
      final result = inspect(elsewhere);
      expect(result.rejection, PolicyRejection.untrustedUnsigned);
      expect(result.discovery, PolicyDiscovery.environmentVariable);
    });

    test('a signed file verifies from either route', () {
      expect(inspect(write(wellKnown(), signed(policy))).wasLoaded, isTrue);
      expect(
        inspect(
          write(p.join(dir.path, 'share.json'), signed(policy)),
        ).wasLoaded,
        isTrue,
      );
    });

    test(
      'an unsigned file at a world-writable well-known path is refused',
      () async {
        final path = write(wellKnown(), policy);
        await chmod('o+w', dir.path);
        final result = inspect(path);
        expect(result.rejection, PolicyRejection.insecurePath);
      },
      skip: posix ? false : 'POSIX modes only',
    );

    test('the same path spelled differently is still the well-known one', () {
      write(wellKnown(), policy);
      final spelled = p.join(dir.path, '.', 'sub', '..', '.crux-policy.json');
      expect(inspect(spelled).wasLoaded, isTrue);
    });
  });

  group("the installed key is read under the loader's rules", () {
    test(
      'a world-writable INSTALLED key is ignored, exactly as a product does',
      () async {
        // Before, the bytes were taken as given and verified clean — the
        // rollout check passed on a machine that refuses the file.
        final keyPath = installKey();
        await chmod('o+w', keyPath);
        final result = inspect(
          write(p.join(dir.path, 'share.json'), signed(policy)),
          keyPath: keyPath,
        );
        expect(result.rejection, PolicyRejection.noPublicKey);
        expect(result.keyStatus, PolicyKeyStatus.insecure);
      },
      skip: posix ? false : 'POSIX modes only',
    );

    test(
      "the administrator's own copy of the key is taken as given",
      () async {
        // A key in a scratch directory is not an installed trust root.
        // Refusing it for sitting somewhere writable would make the
        // diagnostic useless on the machine that holds the private key.
        final scratch = Directory(p.join(dir.path, 'scratch'))..createSync();
        final keyPath = p.join(scratch.path, 'org-public.key');
        File(keyPath).writeAsStringSync(base64.encode(org.publicKey));
        await chmod('o+w', scratch.path);
        final result = inspect(
          write(p.join(dir.path, 'share.json'), signed(policy)),
          keyPath: keyPath,
        );
        expect(result.wasLoaded, isTrue, reason: result.detail);
        expect(result.keyStatus, PolicyKeyStatus.configured);
      },
      skip: posix ? false : 'POSIX modes only',
    );
  });

  test('the shell environment cannot substitute a different file', () {
    // A CRUX_POLICY exported in the administrator's shell must not change
    // which file `inspect FILE` judges.
    final elsewhere = p.join(dir.path, 'share.json');
    expect(
      inspectionLoader(
        policyPath: elsewhere,
        suppliedKey: org.publicKey,
        wellKnownPath: wellKnown(),
      ).environment,
      {'CRUX_POLICY': elsewhere},
    );
    expect(
      inspectionLoader(
        policyPath: wellKnown(),
        suppliedKey: org.publicKey,
        wellKnownPath: wellKnown(),
      ).environment,
      isEmpty,
    );
  });
}
