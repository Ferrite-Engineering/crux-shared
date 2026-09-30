// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_policy/crux_policy.dart'
    show PolicyPublicKey, kPolicyPublicKeyFileName;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/policy_signer.dart';

/// The `crux-policy` CLI, driven as CI would drive it.
///
/// Exit codes are a contract: a pipeline step branches on them, so they are
/// asserted rather than assumed.
void main() {
  late Directory dir;
  final cli = p.join(Directory.current.path, 'bin', 'crux_policy.dart');

  setUp(() => dir = Directory.systemTemp.createTempSync('crux_policy_cli_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final dart = _dartExecutable();

  ProcessResult run(List<String> args) =>
      Process.runSync(dart, ['run', cli, ...args]);

  String write(String name, Object body) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(body is String ? body : jsonEncode(body));
    return path;
  }

  final seed = List<int>.generate(32, (i) => i);
  final policy = <String, Object?>{
    'schema': 1,
    'org': 'Example',
    'suite': <String, Object?>{
      'telemetry': 'deny',
      'updateChannel': <String, Object?>{'value': 'pinned', 'locked': true},
      'pinnedVersion': '1.0.0',
    },
  };

  Map<String, Object?> signed() => <String, Object?>{
    ...policy,
    'signature': base64.encode(
      signPolicyDocument(document: policy, privateSeed: seed),
    ),
  };

  group('exit codes are a contract', () {
    test('a clean file lints 0', () {
      expect(run(['lint', write('ok.json', policy)]).exitCode, 0);
    });

    test('findings lint 1, and every one is reported at once', () {
      final path = write('bad.json', {
        'schema': 1,
        'suite': {
          'telemetry': 'maybe',
          'updateChannel': 'pinned',
          'theme': {'value': 'x', 'locked': 'yes'},
        },
        'products': {'wavcrux': <String, Object?>{}},
      });
      final result = run(['lint', path]);
      expect(result.exitCode, 1);
      final out = result.stdout as String;
      // One run, every problem — an administrator fixing one error per run
      // stops using the tool.
      expect(out, contains('suite.telemetry'));
      expect(out, contains('suite.theme'));
      expect(out, contains('suite.pinnedVersion'));
      expect(out, contains('products.wavcrux'));
    });

    test('a missing file is 3, not a crash', () {
      expect(run(['lint', p.join(dir.path, 'gone.json')]).exitCode, 3);
    });

    test(
      'an unknown command is 64 (EX_USAGE), clear of every outcome code',
      () {
        expect(run(['frobnicate']).exitCode, 64);
      },
    );

    test('tampering is 4', () {
      final body = signed();
      final tampered = <String, Object?>{
        ...body,
        'suite': <String, Object?>{
          ...policy['suite']! as Map<String, Object?>,
          'telemetry': 'allow',
        },
      };
      final keyPath = write('org.pub', base64.encode(policyPublicKeyFor(seed)));
      final result = run([
        'inspect',
        write('tampered.json', tampered),
        '--product',
        'lintcrux',
        '--key',
        keyPath,
      ]);
      expect(result.exitCode, 4);
      expect(result.stderr as String, contains('badSignature'));
    });
  });

  group('machine-readable output for a pipeline', () {
    test('a product key that is spelled wrong is named', () {
      final path = write('typo.json', {
        'schema': 1,
        'products': {
          'wavecrux': {'themePcks': 'x'},
        },
      });
      final result = run(['lint', path]);
      expect(result.exitCode, 1);
      expect(result.stdout as String, contains('products.wavecrux.themePcks'));
      expect(result.stdout as String, contains('check the spelling'));
    });

    test('a registered-but-unhonoured key says so, in those words', () {
      // The two mistakes are different and must read differently. Before this,
      // both were answered with silence: a correctly-spelled key that nothing
      // reads looked exactly like one the product acts on, so an administrator
      // who set a restriction was never told it was not in force.
      final path = write('unhonoured.json', {
        'schema': 1,
        'products': {
          'lintcrux': {
            'mandatoryEngines': <String>['verilator'],
          },
        },
      });
      final result = run(['lint', path]);
      expect(result.exitCode, 1);
      final out = result.stdout as String;
      expect(out, contains('products.lintcrux.mandatoryEngines'));
      expect(out, contains('NOT honoured'));
      expect(out, isNot(contains('check the spelling')));
    });

    test('a key the product does honour is silent', () {
      final path = write('honoured.json', {
        'schema': 1,
        'products': {
          'wavecrux': {
            'themePacks': <String>['/share/themes'],
          },
        },
      });
      expect(run(['lint', path]).exitCode, 0);
    });

    test('lint --json is parseable', () {
      final path = write('bad.json', {
        'schema': 1,
        'suite': {'telemetry': 'maybe'},
      });
      final result = run(['lint', path, '--json']);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(decoded['findings'], isA<List<Object?>>());
      expect(decoded['findings']! as List<Object?>, isNotEmpty);
    });

    test('inspect --json names what is locked', () {
      final keyPath = write('org.pub', base64.encode(policyPublicKeyFor(seed)));
      final result = run([
        'inspect',
        write('signed.json', signed()),
        '--product',
        'lintcrux',
        '--key',
        keyPath,
        '--json',
      ]);
      expect(result.exitCode, 0);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(decoded['signatureChecked'], isTrue);
      final settings = (decoded['settings']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final channel = settings.firstWhere(
        (s) => s['key'] == 'suite.updateChannel',
      );
      expect(channel['locked'], isTrue);
      expect(channel['value'], 'pinned');
    });
  });

  // `suite.audit` was validated only as "is a map" until 2026-09-19, so a file
  // whose every audit key was misspelled linted clean — and a misspelled
  // `path` silently resolves to NoopAuditSink, i.e. an Enterprise customer
  // believing they have an audit trail and having none. L7 §2.7.
  group('suite.audit is validated, not just shape-checked', () {
    test('a misspelled child key is named, and so is the missing path', () {
      final f = write('audit-typos.json', <String, Object?>{
        'schema': 1,
        'suite': <String, Object?>{
          'audit': <String, Object?>{
            'pth': '/tmp/a.jsonl',
            'verbosty': 'verbose',
          },
        },
      });
      final result = run(['lint', f]);
      expect(result.exitCode, isNot(0));
      final out = '${result.stdout}${result.stderr}';
      expect(out, contains('suite.audit.pth'));
      expect(out, contains('suite.audit.verbosty'));
      // The one that actually turns auditing off.
      expect(out, contains('suite.audit.path'));
      expect(out, contains('the audit sink is a no-op'));
    });

    test('a bad verbosity value names the key', () {
      final f = write('audit-verbosity.json', <String, Object?>{
        'schema': 1,
        'suite': <String, Object?>{
          'audit': <String, Object?>{
            'path': '/tmp/a.jsonl',
            'verbosity': 'verbse',
          },
        },
      });
      final result = run(['lint', f]);
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stdout}${result.stderr}',
        contains('suite.audit.verbosity'),
      );
    });

    test('a valid audit block still lints clean', () {
      for (final v in <String>['off', 'normal', 'verbose']) {
        final f = write('audit-ok-$v.json', <String, Object?>{
          'schema': 1,
          'suite': <String, Object?>{
            'audit': <String, Object?>{'path': '/tmp/a.jsonl', 'verbosity': v},
          },
        });
        expect(run(['lint', f]).exitCode, 0, reason: 'verbosity $v');
      }
    });

    test('a locked audit value is unwrapped, not mistaken for a child key', () {
      final f = write('audit-locked.json', <String, Object?>{
        'schema': 1,
        'suite': <String, Object?>{
          'audit': <String, Object?>{
            'path': <String, Object?>{'value': '/tmp/a.jsonl', 'locked': true},
            'verbosity': 'normal',
          },
        },
      });
      expect(run(['lint', f]).exitCode, 0);
    });
  });

  group('the round trip an administrator actually performs', () {
    test('init → sign → inspect, and the public key is emitted', () {
      final authored = p.join(dir.path, 'policy.json');
      expect(run(['init', '--out', authored]).exitCode, 0);
      expect(run(['lint', authored]).exitCode, 0);

      final keyFile = write('org.key', base64.encode(seed));
      final signedPath = p.join(dir.path, 'signed.json');
      final signResult = run([
        'sign',
        authored,
        '--key',
        keyFile,
        '--out',
        signedPath,
      ]);
      expect(signResult.exitCode, 0);
      // The public key is needed on every machine and deriving it by hand is
      // an error nobody should have to make. The message says WHERE it goes,
      // because "configure at install time" once named a step that did not
      // exist.
      expect(
        signResult.stderr as String,
        contains('install this public key as $kPolicyPublicKeyFileName'),
      );
      expect(
        signResult.stderr as String,
        contains('/etc/edacrux/$kPolicyPublicKeyFileName'),
      );

      final pubFile = write('org.pub', base64.encode(policyPublicKeyFor(seed)));
      final inspected = run([
        'inspect',
        signedPath,
        '--product',
        'wavecrux',
        '--key',
        pubFile,
      ]);
      expect(inspected.exitCode, 0);
      expect(inspected.stdout as String, contains('VERIFIED'));
    });

    test('inspect --key takes the PEM openssl writes, like the loader', () {
      // An administrator who generated the key with openssl has a PEM file;
      // the loader accepts it on the machine, so inspect must too, or the
      // rollout check fails on a file the product would honour.
      const spki = <int>[
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, //
        0x00,
      ];
      final pem =
          '-----BEGIN PUBLIC KEY-----\n'
          '${base64.encode([...spki, ...policyPublicKeyFor(seed)])}\n'
          '-----END PUBLIC KEY-----\n';
      final inspected = run([
        'inspect',
        write('signed.json', signed()),
        '--product',
        'lintcrux',
        '--key',
        write('org.pem', pem),
      ]);
      expect(inspected.exitCode, 0, reason: inspected.stderr.toString());
      expect(inspected.stdout as String, contains('VERIFIED'));
    });

    test('inspect --key refuses a file that is not a key, as I/O', () {
      final inspected = run([
        'inspect',
        write('signed.json', signed()),
        '--product',
        'lintcrux',
        '--key',
        write('org.pub', 'ssh-ed25519 AAAA not-this-format'),
      ]);
      expect(inspected.exitCode, 3);
      expect(inspected.stderr as String, contains('not a 32-byte Ed25519'));
    });

    test('inspect without --key still answers, and says it did not check', () {
      // It is a local diagnostic run by the file's owner. Refusing to look
      // would make it useless in the situation it exists for.
      final result = run([
        'inspect',
        write('signed.json', signed()),
        '--product',
        'lintcrux',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout as String, contains('NOT CHECKED'));
      expect(result.stdout as String, contains('[LOCKED]'));
    });
  });

  // A command line is only a contract if a mistake in it is REFUSED. Each of
  // these was accepted and quietly did something else, which is the failure
  // that cannot be diagnosed from a log: the run SUCCEEDED, and it did the
  // wrong thing. Pinned while there is still no published binary whose
  // behaviour this could change.
  group('a mistyped command line is refused, not reinterpreted', () {
    test('an unknown flag is 64, and the message names it', () {
      final result = run(['lint', write('ok.json', policy), '--jso']);
      expect(result.exitCode, 64);
      final err = result.stderr as String;
      expect(err, contains('--jso'));
      // ...and says what it would have taken instead.
      expect(err, contains('--json'));
    });

    test('a flag is only accepted by the subcommand that has it', () {
      // `--json` was stripped before dispatch, so every subcommand appeared
      // to take it and only two did anything with it.
      final result = run([
        'sign',
        write('ok.json', policy),
        '--key',
        write('org.key', base64.encode(seed)),
        '--json',
      ]);
      expect(result.exitCode, 64);
      expect(result.stderr as String, contains('--json'));
    });

    test('an option without its value is 64, not a silent default', () {
      final result = run(['sign', write('ok.json', policy), '--key']);
      expect(result.exitCode, 64);
      expect(result.stderr as String, contains('needs a value'));
    });

    test('a second file is 64 — the first is not checked alone', () {
      final result = run([
        'lint',
        write('a.json', policy),
        write('b.json', policy),
      ]);
      expect(result.exitCode, 64);
    });

    test('init takes no file, and says so rather than ignoring one', () {
      expect(run(['init', write('a.json', policy)]).exitCode, 64);
    });

    test('sign finds its FILE whichever side of --key it is on', () {
      // The file was "the first argument not starting with -", so the PRIVATE
      // KEY path was taken as the policy document and the policy file was
      // never read at all.
      final out = p.join(dir.path, 'signed.json');
      final result = run([
        'sign',
        '--key',
        write('org.key', base64.encode(seed)),
        '--out',
        out,
        write('policy.json', policy),
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final document =
          jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
      expect(document['org'], 'Example');
      expect(document['signature'], isA<String>());
    });

    test('an option value may itself start with a dash', () {
      // Values are taken by POSITION, never sniffed: guessing would make
      // `--out -x.json` silently mean something else.
      final result = run([
        'inspect',
        write('signed.json', signed()),
        '--product',
        '--not-a-product',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout as String, contains('--not-a-product'));
    });
  });

  // Before this, a write failure on --out was an UNCAUGHT
  // FileSystemException: the Dart runtime printed its own multi-line stack
  // trace to stderr and exited 255, which is not in the exit-code table the
  // README publishes. `init` and `sign` are the only two commands that write
  // to a path an administrator names, so both are proven here.
  group('a write failure on --out is I/O, not an uncaught crash', () {
    test('init --out into a directory that does not exist exits 3', () {
      final out = p.join(dir.path, 'nonexistent-subdir', 'policy.json');
      final result = run(['init', '--out', out]);
      expect(result.exitCode, 3);
      expect(File(out).existsSync(), isFalse);
      final err = result.stderr as String;
      // Exactly one line: the documented, deliberate stderr message, not a
      // raw stack trace (255's actual shape before this fix).
      expect(const LineSplitter().convert(err), hasLength(1));
      expect(err, contains('crux-policy:'));
      expect(err, contains(out));
    });

    test('sign --out into a directory that does not exist exits 3', () {
      final out = p.join(dir.path, 'nonexistent-subdir', 'signed.json');
      final result = run([
        'sign',
        write('policy.json', policy),
        '--key',
        write('org.key', base64.encode(seed)),
        '--out',
        out,
      ]);
      expect(result.exitCode, 3);
      expect(File(out).existsSync(), isFalse);
      final err = result.stderr as String;
      expect(const LineSplitter().convert(err), hasLength(1));
      expect(err, contains('crux-policy:'));
      expect(err, contains(out));
    });
  });

  // The administrator's first contact with the tool is the three-line block
  // the deployment procedure prints. Asking any of those for help must ANSWER
  // — on stdout, exit 0. A usage error there reads as "you typed it wrong" on
  // the first thing anyone ever runs.
  group('--help is answered, not refused', () {
    for (final command in const <String>['init', 'lint', 'sign', 'inspect']) {
      test('$command --help exits 0, on stdout', () {
        final result = run([command, '--help']);
        expect(result.exitCode, 0);
        expect(result.stdout as String, contains('crux-policy init'));
        expect(result.stderr as String, isEmpty);
      });

      test('$command -h exits 0', () {
        expect(run([command, '-h']).exitCode, 0);
      });
    }

    test('bare --help exits 0', () {
      expect(run(['--help']).exitCode, 0);
    });

    test('help does not promise comments JSON cannot carry', () {
      // `init` emits plain JSON, which has no comments. The text said
      // "commented starter file", and so did the deployment guide.
      expect(run(['--help']).stdout as String, isNot(contains('commented')));
    });
  });

  group('--version names the release, and is answered anywhere', () {
    test('prints "crux-policy <pubspec version>" on stdout, exit 0', () {
      // The release archive is named from pubspec.yaml; a binary that reports
      // a different number than the file it came in is a support ticket.
      final pubspec = File(
        p.join(Directory.current.path, 'pubspec.yaml'),
      ).readAsStringSync();
      final version = RegExp(
        r'^version:\s*([^\s+]+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;

      final result = run(['--version']);
      expect(result.exitCode, 0);
      expect((result.stdout as String).trim(), 'crux-policy $version');
      expect(result.stderr as String, isEmpty);
    });

    test('after a subcommand, before anything is parsed or read', () {
      final result = run(['inspect', '--version']);
      expect(result.exitCode, 0);
      expect(result.stdout as String, startsWith('crux-policy '));
    });
  });

  group('sign takes the key an administrator actually has', () {
    // RFC 8032 §7.1, TEST 1: a published seed and the public key it derives.
    const rfcSeedHex =
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
    const rfcPublicHex =
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
    List<int> hex(String s) => <int>[
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ];
    // RFC 8410's PKCS#8 wrapper, as `openssl genpkey -algorithm ed25519`
    // writes it.
    const pkcs8Prefix = <int>[
      0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, //
      0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20, //
    ];
    String armour(String label, List<int> der) =>
        '-----BEGIN $label-----\n${base64.encode(der)}\n-----END $label-----\n';

    ProcessResult signWith(String keyText) => run([
      'sign',
      write('policy.json', policy),
      '--key',
      write('org.key', keyText),
      '--out',
      p.join(dir.path, 'signed.json'),
    ]);

    List<String> stderrLines(ProcessResult r) =>
        const LineSplitter().convert(r.stderr as String);

    test("openssl's PKCS#8 PEM signs, and yields the RFC's public key", () {
      // Refusing it sent an administrator off to cut 32 bytes out of DER by
      // hand — the step most likely to produce a wrong key.
      final result = signWith(
        armour('PRIVATE KEY', [...pkcs8Prefix, ...hex(rfcSeedHex)]),
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(stderrLines(result).last, base64.encode(hex(rfcPublicHex)));
    });

    test('the same seed as hex signs to the same key', () {
      final result = signWith(rfcSeedHex);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(stderrLines(result).last, base64.encode(hex(rfcPublicHex)));
    });

    test('the public key is the LAST stderr line, and nothing else', () {
      // The deployment guide captures it with `2>&1 >/dev/null | tail -1`.
      // Any line printed after it would be installed as the trust root.
      final result = signWith(base64.encode(seed));
      final last = stderrLines(result).last;
      expect(last, base64.encode(policyPublicKeyFor(seed)));
      expect(PolicyPublicKey.parse(last).bytes, policyPublicKeyFor(seed));
    });

    test("each install location uses its own platform's separators", () {
      final err = signWith(base64.encode(seed)).stderr as String;
      expect(err, contains(r'\EDACrux\crux-policy.pub'));
      expect(err, isNot(contains('ProgramData/')));
      expect(err, contains('/etc/edacrux/crux-policy.pub'));
    });

    test('a passphrase-protected key is refused, and says what to do', () {
      final result = signWith(
        armour('ENCRYPTED PRIVATE KEY', List<int>.filled(80, 7)),
      );
      expect(result.exitCode, 3);
      expect(result.stderr as String, contains('passphrase'));
    });

    test('a key of the wrong shape is refused with its size', () {
      final result = signWith(base64.encode(List<int>.filled(40, 1)));
      expect(result.exitCode, 3);
      expect(result.stderr as String, contains('not an Ed25519 private key'));
    });
  });

  group('inspect speaks the words a product logs', () {
    Map<String, Object?> tampered() => <String, Object?>{
      ...signed(),
      'suite': <String, Object?>{
        ...policy['suite']! as Map<String, Object?>,
        'telemetry': 'allow',
      },
    };

    List<String> inspectArgs(String file, {bool json = false}) => [
      'inspect',
      file,
      '--product',
      'lintcrux',
      '--key',
      write('org.pub', base64.encode(policyPublicKeyFor(seed))),
      if (json) '--json',
    ];

    test('a refusal names reason= and key=, as the process log does', () {
      final result = run(inspectArgs(write('t.json', tampered())));
      expect(result.exitCode, 4);
      final err = result.stderr as String;
      expect(err, contains('reason=badSignature'));
      expect(err, contains('key=configured'));
    });

    test('under --json a refusal is JSON on stdout, not prose', () {
      // A pipeline that asked for JSON and got an English sentence on stderr
      // could not tell a bad signature from a missing key.
      final result = run(inspectArgs(write('t.json', tampered()), json: true));
      expect(result.exitCode, 4);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      final refused = decoded['refused']! as Map<String, Object?>;
      expect(refused['reason'], 'badSignature');
      expect(refused['key'], 'configured');
      expect(refused['signed'], isTrue);
    });

    test('an honoured file says which key and route judged it', () {
      final result = run(inspectArgs(write('s.json', signed())));
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout as String, contains('key=configured'));
      expect(result.stdout as String, contains('discovery='));
    });

    test('an unsigned file away from the well-known path is refused', () {
      // What a product does with it through CRUX_POLICY.
      final result = run(inspectArgs(write('u.json', policy)));
      expect(result.exitCode, 4);
      expect(result.stderr as String, contains('reason=untrustedUnsigned'));
    });
  });
}

/// A standalone `dart` to run the CLI with.
///
/// Under `dart test` the running executable is the Dart VM and is used as is.
/// Under `flutter test` — which `tool/coverage.sh` runs — it is the Flutter
/// tester, which cannot `run` a script and never exits, so the SDK bundled
/// with Flutter is used instead, then whatever `dart` is on `PATH`.
String _dartExecutable() {
  final running = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(running).startsWith('dart')) return running;
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final bundled = p.join(flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin', exe);
    if (File(bundled).existsSync()) return bundled;
  }
  return exe;
}
