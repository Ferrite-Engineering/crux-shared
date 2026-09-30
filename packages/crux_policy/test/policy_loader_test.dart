// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crux_policy/crux_policy.dart';
import 'package:crux_policy/src/policy_host_stub.dart' as stub;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/ed25519_sign.dart';

/// The loader, and the threat model it exists for: **a policy file arrives
/// from a network share an attacker may be able to write to.**
///
/// The negatives matter more than the positives here, so there are more of
/// them.
void main() {
  late Directory dir;
  late TestEd25519KeyPair org;
  late TestEd25519KeyPair attacker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crux_policy_');
    org = TestEd25519KeyPair.fromSeed(List<int>.filled(32, 9));
    attacker = TestEd25519KeyPair.fromSeed(List<int>.filled(32, 66));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, Map<String, Object?> body) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(jsonEncode(body));
    return path;
  }

  /// The well-known policy path inside [dir]; the key file is its sibling.
  String wellKnownIn(Directory d) => p.join(d.path, '.crux-policy.json');

  /// Installs [key] where the loader looks for it: beside the well-known path.
  String installKey(TestEd25519KeyPair key, {String? encoded}) {
    final path = p.join(dir.path, kPolicyPublicKeyFileName);
    File(path).writeAsStringSync(encoded ?? base64.encode(key.publicKey));
    return path;
  }

  Map<String, Object?> signed(
    Map<String, Object?> body,
    TestEd25519KeyPair key,
  ) {
    final payload = PolicyLoader.canonicalPayload(body);
    return <String, Object?>{
      ...body,
      'signature': base64.encode(key.sign(utf8.encode(payload))),
    };
  }

  final policy = <String, Object?>{
    'schema': 1,
    'org': 'Example Semiconductor',
    'suite': <String, Object?>{
      'telemetry': 'deny',
      'updateChannel': <String, Object?>{'value': 'pinned', 'locked': true},
    },
  };

  /// A loader that finds [path] either through `CRUX_POLICY` (untrusted) or
  /// as the well-known path (trusted), with [key] bound in code. The key
  /// FILE is looked for beside the well-known path either way, so a test
  /// that wants the file route calls [installKey] and passes no [key].
  PolicyLoader loaderFor(String path, {List<int>? key, bool trusted = false}) =>
      PolicyLoader(
        trustedPublicKey: key,
        environment: trusted ? const {} : {'CRUX_POLICY': path},
        wellKnownPath: trusted ? path : p.join(dir.path, 'nonexistent'),
      );

  group('a correctly signed file is honoured', () {
    test('and its keys resolve', () {
      final path = write('signed.json', signed(policy, org));
      final result = loaderFor(path, key: org.publicKey).load();

      expect(result.wasRejected, isFalse);
      expect(result.document.isPresent, isTrue);
      expect(result.document.org, 'Example Semiconductor');
      expect(result.keyStatus, PolicyKeyStatus.configured);
    });

    test('reformatting does not invalidate the signature', () {
      // The signature is over the document with sorted keys, so an
      // administrator who reformats the file in an editor does not get a
      // failure that looks like tampering.
      final body = signed(policy, org);
      final reordered = <String, Object?>{
        'signature': body['signature'],
        'suite': body['suite'],
        'org': body['org'],
        'schema': body['schema'],
      };
      final path = write('reordered.json', reordered);
      expect(loaderFor(path, key: org.publicKey).load().wasRejected, isFalse);
    });
  });

  group('the negatives — every one of these must refuse the whole file', () {
    test('signed by the WRONG KEY', () {
      final path = write('evil.json', signed(policy, attacker));
      final result = loaderFor(path, key: org.publicKey).load();

      expect(result.rejection, PolicyRejection.badSignature);
      expect(result.document.isPresent, isFalse);
    });

    test('a VALID SIGNATURE OVER DIFFERENT CONTENT', () {
      // The lift-and-shift attack: take a legitimately signed file and swap the
      // body. This is the one a naive "is there a signature?" check passes.
      final body = signed(policy, org);
      final tampered = <String, Object?>{
        ...body,
        'suite': <String, Object?>{'telemetry': 'allow'},
      };
      final path = write('tampered.json', tampered);
      final result = loaderFor(path, key: org.publicKey).load();

      expect(result.rejection, PolicyRejection.badSignature);
      expect(result.document.isPresent, isFalse);
    });

    test('a TRUNCATED signature', () {
      final body = signed(policy, org);
      final short = <String, Object?>{
        ...body,
        'signature': (body['signature']! as String).substring(0, 40),
      };
      final path = write('short.json', short);
      expect(
        loaderFor(path, key: org.publicKey).load().rejection,
        PolicyRejection.malformedSignature,
      );
    });

    test('the signature STRIPPED ENTIRELY, from an untrusted path', () {
      // Removing the signature must not be a way to bypass it.
      final path = write('unsigned.json', policy);
      final result = loaderFor(path, key: org.publicKey).load();

      expect(result.rejection, PolicyRejection.untrustedUnsigned);
      expect(result.document.isPresent, isFalse);
    });

    test('signed, but no organization key is installed', () {
      // A signed file nobody verifies is WORSE than an unsigned one, because it
      // looks verified. Its own reason, because the fix — install the key —
      // is not the bad-signature fix.
      final path = write('signed.json', signed(policy, org));
      final result = loaderFor(path).load();

      expect(result.rejection, PolicyRejection.noPublicKey);
      expect(result.keyStatus, PolicyKeyStatus.none);
      expect(result.document.isPresent, isFalse);
      expect(result.detail, contains(kPolicyPublicKeyFileName));
    });

    test('a signature that is not a string', () {
      final path = write('weird.json', {...policy, 'signature': 42});
      expect(
        loaderFor(path, key: org.publicKey).load().rejection,
        PolicyRejection.malformedSignature,
      );
    });
  });

  group('an unsigned file is honoured only from a trusted path', () {
    test('the well-known path is trusted', () {
      // It needs administrator rights to write, which is the trust.
      final path = write('.crux-policy.json', policy);
      final result = loaderFor(path, key: org.publicKey, trusted: true).load();

      expect(result.wasRejected, isFalse);
      expect(result.document.isPresent, isTrue);
    });

    test('CRUX_POLICY is not, when a key is configured', () {
      final path = write('unsigned.json', policy);
      expect(
        loaderFor(path, key: org.publicKey).load().rejection,
        PolicyRejection.untrustedUnsigned,
      );
    });

    test('CRUX_POLICY is not, even when NO key is configured', () {
      // This cell used to be honoured as "the un-deployed default", and the
      // un-deployed default is every machine: an unprivileged process that
      // sets CRUX_POLICY to a file it wrote had its file honoured on any
      // seat where no administrator had installed a key yet — which is the
      // exact attack the signature exists to prevent. A key widens what a
      // SIGNED file may do; it never widens what an unsigned one may.
      final path = write('unsigned.json', policy);
      final result = loaderFor(path).load();

      expect(result.rejection, PolicyRejection.untrustedUnsigned);
      expect(result.document.isPresent, isFalse);
    });
  });

  group('the trust table — every cell, pinned to the published contract', () {
    // <https://edacrux.app/policy-reference#unsigned>. Two axes the loader
    // controls (where the file was found; whether a key is installed) and one
    // the administrator controls (whether they signed it). Eight cells, plus
    // the two bad-signature cells, each with the documented outcome.

    void expectHonoured(PolicyLoadResult result, {required bool signed}) {
      expect(result.wasLoaded, isTrue, reason: result.detail);
      expect(result.wasRejected, isFalse);
      expect(result.document.org, 'Example Semiconductor');
      expect(result.signed, signed);
    }

    void expectRefused(PolicyLoadResult result, PolicyRejection why) {
      expect(result.rejection, why);
      expect(result.wasLoaded, isFalse);
      expect(result.document.isPresent, isFalse);
    }

    test('signed · trusted path · key installed → honoured', () {
      final path = write('.crux-policy.json', signed(policy, org));
      expectHonoured(
        loaderFor(path, key: org.publicKey, trusted: true).load(),
        signed: true,
      );
    });

    test('signed · CRUX_POLICY · key installed → honoured', () {
      // "A file signed by your key is honoured wherever it is found."
      final path = write('anywhere.json', signed(policy, org));
      expectHonoured(loaderFor(path, key: org.publicKey).load(), signed: true);
    });

    test('signed · trusted path · no key → refused (noPublicKey)', () {
      // "A signed file on a machine where no organization public key was
      // configured is refused." Trust in the path does not stand in for a
      // signature check the file asked for.
      final path = write('.crux-policy.json', signed(policy, org));
      expectRefused(
        loaderFor(path, trusted: true).load(),
        PolicyRejection.noPublicKey,
      );
    });

    test('signed · CRUX_POLICY · no key → refused (noPublicKey)', () {
      final path = write('anywhere.json', signed(policy, org));
      expectRefused(loaderFor(path).load(), PolicyRejection.noPublicKey);
    });

    test('unsigned · trusted path · key installed → honoured', () {
      // "With no signature, an unsigned file at the well-known path is
      // honoured" — and installing a key does not withdraw that, or the act
      // of installing the key would break every fleet that had not yet
      // re-signed.
      final path = write('.crux-policy.json', policy);
      expectHonoured(
        loaderFor(path, key: org.publicKey, trusted: true).load(),
        signed: false,
      );
    });

    test('unsigned · trusted path · no key → honoured', () {
      // The genuine un-deployed default: try the mechanism before generating
      // a key, from the one place only an administrator can write.
      final path = write('.crux-policy.json', policy);
      expectHonoured(loaderFor(path, trusted: true).load(), signed: false);
    });

    test('unsigned · CRUX_POLICY · key installed → refused', () {
      final path = write('anywhere.json', policy);
      expectRefused(
        loaderFor(path, key: org.publicKey).load(),
        PolicyRejection.untrustedUnsigned,
      );
    });

    test('unsigned · CRUX_POLICY · no key → refused', () {
      // The cell that was inverted. See the group above for why.
      final path = write('anywhere.json', policy);
      expectRefused(loaderFor(path).load(), PolicyRejection.untrustedUnsigned);
    });

    test('wrong key · trusted path → refused (badSignature)', () {
      // A trusted path does not rescue a signature that fails. "A file whose
      // signature does not verify is refused entirely."
      final path = write('.crux-policy.json', signed(policy, attacker));
      expectRefused(
        loaderFor(path, key: org.publicKey, trusted: true).load(),
        PolicyRejection.badSignature,
      );
    });

    test('wrong key · CRUX_POLICY → refused (badSignature)', () {
      final path = write('anywhere.json', signed(policy, attacker));
      expectRefused(
        loaderFor(path, key: org.publicKey).load(),
        PolicyRejection.badSignature,
      );
    });
  });

  group('the organization key is read from beside the well-known path', () {
    // This is the install-time key configuration. No environment variable, no
    // recompile: a file the administrator drops in the same directory as the
    // policy file, which is the one directory an unprivileged user cannot
    // write. Every production `PolicyLoader()` finds it there, which is what
    // makes a signed file work on a clean machine.

    test('the default constructor has a key source — the guard', () {
      // A production loader is `const PolicyLoader()`, four products over.
      // There is no constructor argument that turns key lookup off; the only
      // way to bypass the file is to bind a key in code, which is more, not
      // less. This pins that the default resolves to the well-known sibling.
      const loader = PolicyLoader();
      expect(
        loader.effectivePublicKeyPath,
        PolicyLoader.defaultPublicKeyPath(),
      );
      expect(
        p.dirname(loader.effectivePublicKeyPath),
        p.dirname(PolicyLoader.defaultWellKnownPath()),
        reason: 'the key lives beside the policy, in the admin-only directory',
      );
      expect(
        p.basename(loader.effectivePublicKeyPath),
        kPolicyPublicKeyFileName,
      );
    });

    test('redirecting the well-known path redirects the key with it', () {
      final loader = PolicyLoader(wellKnownPath: wellKnownIn(dir));
      expect(
        loader.effectivePublicKeyPath,
        p.join(dir.path, kPolicyPublicKeyFileName),
      );
    });

    test('an explicit publicKeyPath wins', () {
      final loader = PolicyLoader(
        wellKnownPath: wellKnownIn(dir),
        publicKeyPath: '/elsewhere/key',
      );
      expect(loader.effectivePublicKeyPath, '/elsewhere/key');
    });

    test(
      'a signed file via CRUX_POLICY verifies against the installed key',
      () {
        // The deployment.html procedure, end to end: sign, install the printed
        // public key beside the well-known path, point a pipeline at the file.
        installKey(org);
        final path = write('pipeline.json', signed(policy, org));
        final result = PolicyLoader(
          environment: {'CRUX_POLICY': path},
          wellKnownPath: wellKnownIn(dir),
        ).load();

        expect(result.wasLoaded, isTrue, reason: result.detail);
        expect(result.signed, isTrue);
        expect(result.keyStatus, PolicyKeyStatus.configured);
        expect(result.discovery, PolicyDiscovery.environmentVariable);
      },
    );

    test('a signed file AT the well-known path verifies too', () {
      installKey(org);
      final path = write('.crux-policy.json', signed(policy, org));
      final result = PolicyLoader(
        environment: const {},
        wellKnownPath: path,
      ).load();

      expect(result.wasLoaded, isTrue, reason: result.detail);
      expect(result.keyStatus, PolicyKeyStatus.configured);
    });

    test('the WRONG installed key refuses, with the key reported present', () {
      installKey(attacker);
      final path = write('pipeline.json', signed(policy, org));
      final result = PolicyLoader(
        environment: {'CRUX_POLICY': path},
        wellKnownPath: wellKnownIn(dir),
      ).load();

      expect(result.rejection, PolicyRejection.badSignature);
      // Distinguishable from "no key": the administrator's next move is to
      // compare fingerprints, not to install one.
      expect(result.keyStatus, PolicyKeyStatus.configured);
    });

    test('a key bound in code outranks the file', () {
      // The `crux-policy inspect --key` seam: the person holding the file
      // names the key, whatever the machine has installed.
      installKey(attacker);
      final path = write('pipeline.json', signed(policy, org));
      final result = PolicyLoader(
        trustedPublicKey: org.publicKey,
        environment: {'CRUX_POLICY': path},
        wellKnownPath: wellKnownIn(dir),
      ).load();
      expect(result.wasLoaded, isTrue);
    });

    test('hex and PEM key files are accepted, not just base64', () {
      final hex = org.publicKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final pem = _pemFor(org.publicKey);
      final path = write('pipeline.json', signed(policy, org));
      for (final encoded in [
        hex,
        pem,
        '# rotated\n${base64.encode(org.publicKey)}\n',
      ]) {
        installKey(org, encoded: encoded);
        final result = PolicyLoader(
          environment: {'CRUX_POLICY': path},
          wellKnownPath: wellKnownIn(dir),
        ).load();
        expect(result.wasLoaded, isTrue, reason: 'encoding:\n$encoded');
      }
    });

    test('a malformed key file refuses a signed file and says so', () {
      installKey(org, encoded: 'ssh-ed25519 AAAAC3Nz not-a-raw-key');
      final path = write('pipeline.json', signed(policy, org));
      final result = PolicyLoader(
        environment: {'CRUX_POLICY': path},
        wellKnownPath: wellKnownIn(dir),
      ).load();

      expect(result.rejection, PolicyRejection.noPublicKey);
      expect(result.keyStatus, PolicyKeyStatus.malformed);
      expect(result.detail, contains('not a 32-byte Ed25519'));
    });

    test('a malformed key file does not touch an unsigned trusted file', () {
      // The key only ever enters the signed branch.
      installKey(org, encoded: 'garbage');
      final path = write('.crux-policy.json', policy);
      final result = PolicyLoader(
        environment: const {},
        wellKnownPath: path,
      ).load();
      expect(result.wasLoaded, isTrue);
      expect(result.keyStatus, PolicyKeyStatus.malformed);
    });

    test('the key status is carried even when there is no policy file', () {
      // So a settings surface can say "a key is installed" before the first
      // signed file ever arrives — or, more usefully, that none is.
      installKey(org);
      final result = PolicyLoader(
        environment: const {},
        wellKnownPath: wellKnownIn(dir),
      ).load();
      expect(result.discovery, PolicyDiscovery.none);
      expect(result.keyStatus, PolicyKeyStatus.configured);
    });

    test('there is no environment variable for the key, by design', () {
      // An env-settable trust root is what an unprivileged process can set:
      // it would sign its own policy and point the app at both. The only
      // override is a constructor argument, which a process cannot reach.
      installKey(attacker);
      final path = write('pipeline.json', signed(policy, org));
      final result = PolicyLoader(
        environment: {
          'CRUX_POLICY': path,
          'CRUX_POLICY_PUBLIC_KEY': p.join(dir.path, 'org.pub'),
          'CRUX_POLICY_KEY': p.join(dir.path, 'org.pub'),
        },
        wellKnownPath: wellKnownIn(dir),
      ).load();
      expect(result.rejection, PolicyRejection.badSignature);
    });

    test('defaultPublicKeyPath sits beside the policy on every platform', () {
      for (final os in ['macos', 'windows', 'linux', 'web']) {
        // Judged by THAT platform's path rules. Using the host's here is how
        // a Windows path built with `/` on a Mac passed this test.
        final paths = os == 'windows' ? p.windows : p.posix;
        final key = PolicyLoader.defaultPublicKeyPath(operatingSystem: os);
        final policyPath = PolicyLoader.defaultWellKnownPath(
          operatingSystem: os,
        );
        expect(paths.dirname(key), paths.dirname(policyPath), reason: os);
        expect(paths.basename(key), kPolicyPublicKeyFileName, reason: os);
        expect(
          paths.basename(policyPath),
          PolicyLoader.policyFileName,
          reason: os,
        );
      }
      expect(
        PolicyLoader.defaultPublicKeyPath(operatingSystem: 'macos'),
        '/Library/Application Support/EDACrux/crux-policy.pub',
      );
      expect(
        PolicyLoader.defaultPublicKeyPath(operatingSystem: 'linux'),
        '/etc/edacrux/crux-policy.pub',
      );
    });

    test('a Windows path uses Windows separators, whatever the host', () {
      // `crux-policy sign` names all three install locations from whichever
      // machine the administrator signs on. Built with the host's rules, a
      // Mac printed `C:\ProgramData/EDACrux/crux-policy.pub`.
      final key = PolicyLoader.defaultPublicKeyPath(operatingSystem: 'windows');
      final policyPath = PolicyLoader.defaultWellKnownPath(
        operatingSystem: 'windows',
      );
      expect(key, isNot(contains('/')));
      expect(policyPath, isNot(contains('/')));
      expect(key, endsWith(r'\EDACrux\crux-policy.pub'));
      expect(policyPath, endsWith(r'\EDACrux\.crux-policy.json'));

      // …and a POSIX path keeps POSIX separators on a Windows host.
      expect(
        PolicyLoader.defaultWellKnownPath(operatingSystem: 'macos'),
        '/Library/Application Support/EDACrux/.crux-policy.json',
      );
    });
  });

  group('a world-writable well-known location is not a trusted one', () {
    // The trusted-path branch rests on ONE property: the directory needs
    // administrator rights to write. macOS ships no installer that creates it
    // and Linux packages can be unpacked by hand, so the property has to be
    // checked rather than assumed. POSIX only; Windows has an ACL, not a mode.
    final posix = !Platform.isWindows;

    Future<void> chmod(String mode, String path) async {
      final r = await Process.run('chmod', [mode, path]);
      expect(r.exitCode, 0, reason: r.stderr.toString());
    }

    test('an unsigned file in a world-writable directory is refused', () async {
      final path = write('.crux-policy.json', policy);
      await chmod('o+w', dir.path);
      final result = PolicyLoader(
        environment: const {},
        wellKnownPath: path,
      ).load();

      expect(result.rejection, PolicyRejection.insecurePath);
      expect(result.detail, contains('writable by every user'));
      expect(result.document.isPresent, isFalse);
    }, skip: posix ? false : 'POSIX modes only');

    test('a world-writable unsigned file is refused too', () async {
      final path = write('.crux-policy.json', policy);
      await chmod('o+w', path);
      expect(
        PolicyLoader(
          environment: const {},
          wellKnownPath: path,
        ).load().rejection,
        PolicyRejection.insecurePath,
      );
    }, skip: posix ? false : 'POSIX modes only');

    test(
      'a SIGNED file in a world-writable directory is still honoured',
      () async {
        // The signature is the control there, and it holds regardless of who
        // can write the directory — that is the whole point of having one.
        installKey(org);
        final path = write('.crux-policy.json', signed(policy, org));
        await chmod('o+w', dir.path);
        final result = PolicyLoader(
          environment: const {},
          wellKnownPath: path,
        ).load();
        // …except that the KEY beside it is now replaceable too, so it cannot
        // vouch for anything. Refused, and the detail says which fix.
        expect(result.rejection, PolicyRejection.noPublicKey);
        expect(result.keyStatus, PolicyKeyStatus.insecure);
      },
      skip: posix ? false : 'POSIX modes only',
    );

    test('a world-writable KEY FILE is ignored', () async {
      final keyPath = installKey(org);
      await chmod('o+w', keyPath);
      final path = write('pipeline.json', signed(policy, org));
      final result = PolicyLoader(
        environment: {'CRUX_POLICY': path},
        wellKnownPath: wellKnownIn(dir),
      ).load();

      expect(result.rejection, PolicyRejection.noPublicKey);
      expect(result.keyStatus, PolicyKeyStatus.insecure);
      expect(result.detail, contains('restrict it to administrators'));
    }, skip: posix ? false : 'POSIX modes only');

    test('group-writable is not world-writable', () async {
      // macOS's /Library/Application Support is root:admin 0775 by Apple's
      // design, and the admin group is the privileged one. Refusing that
      // would refuse every Mac.
      final path = write('.crux-policy.json', policy);
      await chmod('g+w', dir.path);
      await chmod('g+w', path);
      expect(
        PolicyLoader(
          environment: const {},
          wellKnownPath: path,
        ).load().wasLoaded,
        isTrue,
      );
    }, skip: posix ? false : 'POSIX modes only');
  });

  group('missing is ABSENT, not rejected — failing closed bricks a fleet', () {
    test('no file anywhere', () {
      const loader = PolicyLoader(environment: <String, String>{});
      final result = loader.load();
      expect(result.document.isPresent, isFalse);
      expect(result.wasRejected, isFalse);
    });

    test('CRUX_POLICY points at nothing', () {
      final result = loaderFor(p.join(dir.path, 'gone.json')).load();
      expect(result.wasRejected, isFalse, reason: 'a typo is not an attack');
    });

    test('the file is not JSON', () {
      final path = p.join(dir.path, 'garbage.json');
      File(path).writeAsStringSync('{{{ not json');
      final result = loaderFor(path, key: org.publicKey).load();
      expect(result.wasRejected, isFalse);
      expect(result.document.isPresent, isFalse);
      expect(result.keyStatus, PolicyKeyStatus.configured);
    });

    test('the top level is an array', () {
      final path = p.join(dir.path, 'array.json');
      File(path).writeAsStringSync('[1, 2, 3]');
      expect(loaderFor(path).load().document.isPresent, isFalse);
    });

    test('a host that cannot provide an environment at all', () {
      // A browser: `Platform.environment` throws UnsupportedError there, and
      // every product reads the policy file before its first frame.
      final wellKnown = write('.crux-policy.json', policy);
      final loader = PolicyLoader(
        environment: const _UnavailableEnvironment(),
        wellKnownPath: wellKnown,
      );

      late PolicyLoadResult result;
      expect(() => result = loader.load(), returnsNormally);
      expect(result.wasRejected, isFalse);
      expect(
        result.document.org,
        'Example Semiconductor',
        reason:
            'no override is readable, so discovery falls through to the '
            'well-known path',
      );
    });

    test('CRUX_POLICY wins over the well-known path', () {
      // First hit wins, and they are NOT merged. Both signed, because an
      // unsigned CRUX_POLICY file is refused rather than compared.
      installKey(org);
      final explicit = write(
        'explicit.json',
        signed({...policy, 'org': 'From CRUX_POLICY'}, org),
      );
      final wellKnown = write('.crux-policy.json', {
        ...policy,
        'org': 'From the well-known path',
      });
      final loader = PolicyLoader(
        environment: {'CRUX_POLICY': explicit},
        wellKnownPath: wellKnown,
      );
      expect(loader.load().document.org, 'From CRUX_POLICY');
    });
  });

  group('the host a browser gets', () {
    // The conditional export picks this stub wherever `dart:io` is missing.
    // `policy_loader_web_test.dart` runs the loader through it on Chrome; this
    // pins the stub's own answers on the VM, where it is otherwise never
    // loaded.
    test('sees no environment and no file, even one that exists', () {
      final path = write('.crux-policy.json', policy);

      expect(stub.hostEnvironment(), isEmpty);
      expect(stub.hostFileExists(path), isFalse);
      expect(stub.hostIsWorldWritable(path), isFalse);
      expect(() => stub.hostReadFile(path), throwsUnsupportedError);
    });

    test('its operating system selects the generic well-known path', () {
      expect(
        PolicyLoader.defaultWellKnownPath(
          operatingSystem: stub.hostOperatingSystem(),
        ),
        '/etc/edacrux/.crux-policy.json',
      );
    });
  });

  group('which file won, without naming the file', () {
    // The two fields a report is built from. `sourcePath` cannot be the
    // answer — CRUX_POLICY can point at a home directory and no audit payload
    // in the suite carries a filesystem path — so the loader records the
    // discovery SOURCE, of which there are exactly two.

    test('the well-known path is stamped, and a plain file is unsigned', () {
      final path = write('.crux-policy.json', policy);
      final result = loaderFor(path, trusted: true).load();

      expect(result.discovery, PolicyDiscovery.wellKnownPath);
      expect(result.signed, isFalse);
      expect(result.wasLoaded, isTrue);
      expect(result.wasRejected, isFalse);
    });

    test('CRUX_POLICY is stamped, and a signed file says so', () {
      final path = write('.crux-policy.json', signed(policy, org));
      final result = loaderFor(path, key: org.publicKey).load();

      expect(result.discovery, PolicyDiscovery.environmentVariable);
      expect(result.signed, isTrue);
      expect(result.wasLoaded, isTrue);
    });

    test('a refused file keeps both, which is what makes it diagnosable', () {
      // The ordinary attack: the share was written by somebody else.
      final path = write('.crux-policy.json', signed(policy, attacker));
      final result = loaderFor(path, key: org.publicKey).load();

      expect(result.wasRejected, isTrue);
      expect(result.rejection, PolicyRejection.badSignature);
      // `signed` is true and the file was still refused. The pair is the
      // answer: there WAS a file, and it was not trusted.
      expect(result.signed, isTrue);
      expect(result.discovery, PolicyDiscovery.environmentVariable);
      expect(result.wasLoaded, isFalse);
    });

    test(
      'no file at all is discovery.none, and neither loaded nor rejected',
      () {
        final result = PolicyLoader(
          environment: const {},
          wellKnownPath: p.join(dir.path, 'nonexistent'),
        ).load();

        expect(result.discovery, PolicyDiscovery.none);
        expect(result.wasLoaded, isFalse);
        expect(result.wasRejected, isFalse);
      },
    );

    test(
      'CRUX_POLICY pointing at nothing is none, not environmentVariable',
      () {
        // The variable is set, so the well-known path is never consulted — but
        // no file was found, and reporting the variable as the source of a file
        // that does not exist would answer "which file won" with one that never
        // did.
        final result = PolicyLoader(
          environment: {'CRUX_POLICY': p.join(dir.path, 'nonexistent')},
          wellKnownPath: write('.crux-policy.json', policy),
        ).load();

        expect(result.discovery, PolicyDiscovery.none);
        expect(result.wasLoaded, isFalse);
        expect(result.document.org, isNull);
      },
    );
  });
}

/// The SubjectPublicKeyInfo PEM `openssl pkey -pubout` writes for Ed25519.
String _pemFor(List<int> publicKey) {
  const prefix = <int>[
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00, //
  ];
  final body = base64.encode([...prefix, ...publicKey]);
  final wrapped = <String>[
    for (var i = 0; i < body.length; i += 64)
      body.substring(i, i + 64 > body.length ? body.length : i + 64),
  ].join('\n');
  return '-----BEGIN PUBLIC KEY-----\n$wrapped\n-----END PUBLIC KEY-----\n';
}

/// An environment that cannot be read at all — what `Platform.environment` is
/// on the web, where every access throws.
class _UnavailableEnvironment extends MapBase<String, String> {
  const _UnavailableEnvironment();

  Never _unavailable() => throw UnsupportedError('Platform._environment');

  @override
  String? operator [](Object? key) => _unavailable();

  @override
  void operator []=(String key, String value) => _unavailable();

  @override
  void clear() => _unavailable();

  @override
  Iterable<String> get keys => _unavailable();

  @override
  String? remove(Object? key) => _unavailable();
}
