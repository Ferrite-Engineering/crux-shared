// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The `crux-policy` CLI: author, lint, sign and inspect `.crux-policy.json`.
//
// THIS IS THE ENTIRE REPLACEMENT FOR AN ADMIN CONSOLE. There is no console and
// there will not be one. Keygen already owns seats, entitlements and usage
// reporting; the only thing left for an administrator to do is author a
// document, and a CLI does that with no hosting, no auth, no tenancy and no
// frontend.
//
// ── WHERE THE SIGNER LIVES ──────────────────────────────────────────────────
//
// `crux_signing` verifies and cannot sign. `sign` here needs a real signer,
// and the constraint is absolute: NO PRODUCT BUILD MAY CONTAIN SIGNING CODE,
// because that is what keeps open core free of non-exempt encryption for
// export control, and every store listing's
// `ITSAppUsesNonExemptEncryption=false` true.
//
// The decision: the signer lives in `tool/policy_signer.dart` in this package
// and is reachable ONLY from `bin/`. It is not exported from the package
// barrel, so nothing that imports `package:crux_policy/crux_policy.dart` can
// reach it — and every product imports exactly that. The export-control guard
// resolves each product's real dependency closure, so the proof is mechanical
// rather than a promise: if this leaked into a product, that guard fails.
//
// A `dev_dependency` on a separate signing package was the other candidate
// and is worse: it would put a signer in the resolved dev closure of every
// consumer of this package, and "dev dependencies do not ship" is a claim
// about a build system rather than a fact about the source tree.
//
// ── Behaviour ────────────────────────────────────────────────────────────────
//
// Exit codes mean something, output can be machine-readable, and nothing
// prompts — this drops into CI and config-management pipelines, which is what a
// web console cannot do. LintCrux's plan makes the point that keeping the
// policy file in git gives a team a better change history for rule policy than
// a console would; this is what makes that true, so it behaves like a
// git-friendly tool.
//
// The command line follows the suite's headless-tool conventions: a usage
// error is 64 (EX_USAGE), clear of every outcome code a pipeline branches on;
// `--help` and `--version` are answered on stdout with 0 wherever they appear;
// and a signal is left to terminate the process, so a cancelled job reports
// 128 + the signal number rather than anything this file chose.

import 'dart:convert';
import 'dart:io';

import 'package:crux_policy/crux_policy.dart';
import 'package:crux_policy/src/policy_inspect.dart';
import 'package:crux_policy/src/policy_lint.dart';

import '../tool/policy_signer.dart';

/// The version `--version` prints. `test/cli_test.dart` holds it to the
/// `version:` in `pubspec.yaml`, which is also what names the release archive.
const String kCruxPolicyVersion = '0.1.0';

/// Exit codes. Stable: CI steps branch on these.
const int _ok = 0;
const int _lintFindings = 1;
const int _ioError = 3;
const int _refused = 4;

/// `EX_USAGE`. Deliberately far from the outcome codes above, so a step that
/// branches on "findings" can never mistake a typo in its own command line
/// for one.
const int _usage = 64;

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv);
}

Future<int> _run(List<String> argv) async {
  if (argv.isEmpty) return _printUsage();

  // Help and version are answered wherever they appear — before the command,
  // after it, or after its options — and before anything is read. `--help`
  // AFTER a subcommand asks for help; it is not a malformed invocation, and
  // answering it with the code that means "you got this wrong" is how a tool
  // teaches an administrator to stop asking it anything. The deployment
  // procedure hands them these four subcommands as the first thing they ever
  // run.
  if (argv.contains('-h') || argv.contains('--help') || argv.first == 'help') {
    return _printUsage();
  }
  if (argv.contains('--version')) {
    stdout.writeln('crux-policy $kCruxPolicyVersion');
    return _ok;
  }

  final command = argv.first;
  final rest = argv.skip(1).toList();

  final spec = _specs[command];
  if (spec == null) return _printUsage(unknown: command);

  final args = _parse(command, rest, spec);
  if (args == null) return _usage;

  return switch (command) {
    'lint' => _lint(args),
    'sign' => _sign(args),
    'inspect' => _inspect(args),
    'init' => _init(args),
    _ => _printUsage(unknown: command),
  };
}

int _printUsage({String? unknown}) {
  final out = unknown == null ? stdout : stderr;
  if (unknown != null) out.writeln('crux-policy: unknown command "$unknown"\n');
  out.writeln('''
crux-policy $kCruxPolicyVersion — author, lint, sign and inspect .crux-policy.json

  crux-policy init [--out FILE]
      Emit a starter file to edit.

  crux-policy lint FILE [--json]
      Report every problem at once. Exit $_lintFindings if any are found.

  crux-policy sign FILE --key PRIVATE_KEY_FILE [--out FILE]
      Sign with your organization's own Ed25519 private key: a 32-byte seed
      as base64 or hex, or the PEM file `openssl genpkey -algorithm ed25519`
      writes. The matching public key is the last line printed on stderr.

  crux-policy inspect FILE --product PRODUCT [--key PUBLIC_KEY_FILE] [--json]
      Show what the file resolves to, and which values are locked.
      The "why is my setting greyed out" answer. With --key, the file is
      judged as a product on this machine would judge it where it is.

  crux-policy --help | --version

Exit codes: $_ok ok · $_lintFindings lint findings · $_ioError I/O ·
            $_refused refused (the file would not be honoured) · $_usage usage
''');
  return unknown == null ? _ok : _usage;
}

/// What each subcommand accepts: how many positional FILEs it takes, which
/// options carry a value, and which are bare flags.
typedef _Spec = ({int files, Set<String> valued, Set<String> flags});

const Map<String, _Spec> _specs = <String, _Spec>{
  'init': (files: 0, valued: {'--out'}, flags: <String>{}),
  'lint': (files: 1, valued: <String>{}, flags: {'--json'}),
  'sign': (files: 1, valued: {'--key', '--out'}, flags: <String>{}),
  'inspect': (files: 1, valued: {'--product', '--key'}, flags: {'--json'}),
};

/// One parsed invocation of a subcommand.
class _Args {
  const _Args(this.files, this._valued, this._flags);

  /// The positional arguments, at most as many as the spec allows.
  final List<String> files;

  final Map<String, String> _valued;
  final Set<String> _flags;

  /// The single positional FILE, or null when none was given.
  String? get file => files.isEmpty ? null : files.first;

  /// The value given for [name], or null when the option was not passed.
  String? option(String name) => _valued[name];

  bool get asJson => _flags.contains('--json');
}

/// Parses [argv] against [spec]; on a bad command line says why on stderr and
/// answers null, which the caller turns into [_usage].
///
/// Every token starting with `-` must be an option the subcommand takes, and
/// a stray extra FILE is refused too. IGNORING either is worse than any exit
/// code, because the run then SUCCEEDS having done something other than what
/// was written: `--jso` for `--json` prints human output that the pipeline
/// parses as JSON and fails on somewhere else entirely, and a second file
/// exits 0 having checked only the first.
///
/// This is why the option table is per subcommand rather than global. A flag
/// stripped before dispatch is accepted everywhere, so `sign FILE --json`
/// looked like a request for machine-readable output and was silently not one.
_Args? _parse(String command, List<String> argv, _Spec spec) {
  void reject(String message) {
    final accepted = <String>[...spec.valued, ...spec.flags];
    stderr.writeln('crux-policy: $message');
    if (accepted.isNotEmpty) {
      stderr.writeln('$command accepts: ${accepted.join(' ')}');
    }
  }

  final files = <String>[];
  final valued = <String, String>{};
  final flags = <String>{};

  for (var i = 0; i < argv.length; i++) {
    final token = argv[i];
    if (!token.startsWith('-')) {
      if (files.length == spec.files) {
        reject(
          spec.files == 0
              ? '$command takes no file, and got "$token"'
              : '$command takes one file, and got a second: "$token"',
        );
        return null;
      }
      files.add(token);
      continue;
    }
    if (spec.flags.contains(token)) {
      flags.add(token);
      continue;
    }
    if (spec.valued.contains(token)) {
      // The value is taken by POSITION, never sniffed: a key path or an
      // output path is allowed to start with `-`, and guessing would make
      // `--out -x.json` silently mean something else.
      if (i + 1 >= argv.length) {
        reject('$command $token needs a value');
        return null;
      }
      valued[token] = argv[++i];
      continue;
    }
    reject('$command does not take "$token"');
    return null;
  }

  return _Args(files, valued, flags);
}

int _lint(_Args args) {
  final path = args.file;
  if (path == null) return _printUsage(unknown: 'lint (no file)');

  final String source;
  try {
    source = File(path).readAsStringSync();
  } on Object catch (error) {
    stderr.writeln('crux-policy: cannot read $path — $error');
    return _ioError;
  }

  final findings = lintPolicySource(source);
  if (args.asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'file': path,
        'findings': [
          for (final f in findings) {'key': f.key, 'reason': f.reason},
        ],
      }),
    );
  } else if (findings.isEmpty) {
    stdout.writeln('$path: no problems found');
  } else {
    for (final f in findings) {
      stdout.writeln('$path: ${f.key}: ${f.reason}');
    }
    stdout.writeln('\n${findings.length} finding(s)');
  }
  return findings.isEmpty ? _ok : _lintFindings;
}

int _sign(_Args args) {
  final path = args.file;
  final keyPath = args.option('--key');
  if (path == null || keyPath == null) {
    return _printUsage(unknown: 'sign (need FILE and --key)');
  }

  final Map<String, Object?> document;
  final List<int> seed;
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      stderr.writeln('crux-policy: $path is not a JSON object');
      return _ioError;
    }
    document = decoded;
    seed = _readSeed(File(keyPath).readAsStringSync());
  } on Object catch (error) {
    stderr.writeln('crux-policy: $error');
    return _ioError;
  }

  final signature = signPolicyDocument(document: document, privateSeed: seed);
  final signed = <String, Object?>{
    for (final e in document.entries)
      if (e.key != 'signature') e.key: e.value,
    'signature': base64.encode(signature),
  };
  final rendered = '${const JsonEncoder.withIndent('  ').convert(signed)}\n';

  final out = args.option('--out');
  if (out == null) {
    stdout.write(rendered);
  } else {
    try {
      File(out).writeAsStringSync(rendered);
    } on FileSystemException catch (error) {
      stderr.writeln('crux-policy: cannot write $out — $error');
      return _ioError;
    }
    stdout.writeln('signed → $out');
  }
  // The corresponding PUBLIC key, because it is needed on every machine and an
  // administrator who has to derive it themselves will get it wrong. This is
  // the only place it can be produced without shipping a signer in a product.
  // Named with WHERE it goes: "configure at install time" described a step
  // that did not exist, and a signed file on a machine without the key is
  // refused.
  //
  // THE KEY IS THE LAST LINE, and nothing may ever be printed after it: the
  // deployment guide captures it with `2>&1 >/dev/null | tail -1`.
  stderr.writeln(
    'install this public key as $kPolicyPublicKeyFileName beside the '
    'well-known policy file on every machine '
    '(${PolicyLoader.defaultPublicKeyPath(operatingSystem: 'macos')}, '
    '${PolicyLoader.defaultPublicKeyPath(operatingSystem: 'windows')}, '
    '${PolicyLoader.defaultPublicKeyPath(operatingSystem: 'linux')}):\n'
    '${base64.encode(policyPublicKeyFor(seed))}',
  );
  return _ok;
}

/// A 32-byte Ed25519 seed, from base64, hex, or the PKCS#8 PEM that
/// `openssl genpkey -algorithm ed25519` writes.
///
/// PEM matters because it is what an administrator gets when they follow
/// "generate the key however your organization generates key material" with
/// the tool every platform ships. Refusing it sent them off to extract 32
/// bytes from DER by hand, which is exactly the kind of step that produces a
/// wrong key. The public-key side already accepts openssl's PEM; this makes
/// the pair symmetric.
List<int> _readSeed(String text) {
  if (text.contains('ENCRYPTED PRIVATE KEY')) {
    throw const FormatException(
      'the private key is passphrase-protected; write an unencrypted copy '
      'for signing with `openssl pkey -in KEY -out PLAIN`',
    );
  }
  // Same line handling as the public-key parser: PEM armour, blank lines and
  // `#` comments are not part of the key.
  final body = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .where((line) => !line.startsWith('-----'))
      .join();

  final hex = RegExp(r'^[0-9a-fA-F]{64}$');
  if (hex.hasMatch(body)) {
    return [
      for (var i = 0; i < 64; i += 2)
        int.parse(body.substring(i, i + 2), radix: 16),
    ];
  }
  final bytes = base64.decode(body);
  if (bytes.length == 32) return bytes;
  if (bytes.length == _pkcs8Ed25519Prefix.length + 32 &&
      _startsWith(bytes, _pkcs8Ed25519Prefix)) {
    return bytes.sublist(_pkcs8Ed25519Prefix.length);
  }
  throw FormatException(
    'not an Ed25519 private key: expected a 32-byte seed (base64 or hex) or '
    "openssl's PKCS#8 PEM, got ${bytes.length} bytes",
  );
}

/// DER `SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING {
/// OCTET STRING (32) } }` — RFC 8410's PKCS#8 wrapper around an Ed25519 seed,
/// byte for byte what `openssl genpkey -algorithm ed25519` emits (measured,
/// OpenSSL 3.6).
const List<int> _pkcs8Ed25519Prefix = <int>[
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, //
  0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20, //
];

bool _startsWith(List<int> bytes, List<int> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

int _inspect(_Args args) {
  final path = args.file;
  final product = args.option('--product');
  if (path == null || product == null) {
    return _printUsage(unknown: 'inspect (need FILE and --product)');
  }

  final String source;
  try {
    source = File(path).readAsStringSync();
  } on Object catch (error) {
    stderr.writeln('crux-policy: cannot read $path — $error');
    return _ioError;
  }

  final keyPath = args.option('--key');
  List<int>? publicKey;
  if (keyPath != null) {
    // The same parser the loader uses on the installed file, so a key that
    // inspects clean here is a key that verifies on the machine — base64,
    // hex or PEM alike.
    final String text;
    try {
      text = File(keyPath).readAsStringSync();
    } on Object catch (error) {
      stderr.writeln('crux-policy: cannot read $keyPath — $error');
      return _ioError;
    }
    final parsed = PolicyPublicKey.parse(text);
    publicKey = parsed.bytes;
    if (publicKey == null) {
      stderr.writeln(
        'crux-policy: $keyPath is not a 32-byte Ed25519 public key '
        '(base64, hex or PEM)',
      );
      return _ioError;
    }
  }

  // Inspect is a LOCAL DIAGNOSTIC run by the person holding the file, and its
  // job is to answer "why is my setting greyed out". Refusing to look because
  // no public key was supplied would make it useless in exactly the situation
  // it exists for. So: with no --key it reports the file unverified and says
  // so on its own output.
  //
  // With --key it answers what a product on THIS machine would do with the
  // file where it is — the published instruction is to run it on the machine,
  // against the exact path that machine reads. That means the loader's own
  // trust rules, not a stricter or looser copy of them: an unsigned file AT
  // the well-known path is honoured unless that location is writable by every
  // user, one anywhere else is refused, and the installed key file is ignored
  // when every user can replace it. See `inspectionLoader`.
  final PolicyDocument doc;
  PolicyLoadResult? verified;
  if (publicKey == null) {
    doc = PolicyDocument.parse(source);
  } else {
    final result = inspectionLoader(
      policyPath: path,
      suppliedKey: publicKey,
      suppliedKeyPath: keyPath,
    ).load();
    if (result.wasRejected) {
      // Named the way every product names it in its process log —
      // `reason=… key=…` — so the line an administrator sees here is the line
      // they will grep for there. `key=` separates "no key installed" from
      // "a key file nobody may trust", which are different fixes.
      if (args.asJson) {
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert({
            'file': path,
            'product': product,
            'refused': _describeLoad(result),
          }),
        );
      } else {
        stderr.writeln(
          'crux-policy: refused (reason=${result.rejection!.name} '
          'key=${result.keyStatus.name} '
          'discovery=${result.discovery.name})'
          '${result.detail == null ? '' : ' — ${result.detail}'}',
        );
      }
      return _refused;
    }
    doc = result.document;
    verified = result;
  }
  final rows = <Map<String, Object?>>[
    for (final e in doc.suite.entries)
      {'key': 'suite.${e.key}', ..._describe(e.value)},
    for (final e
        in (doc.products[product] ?? const <String, Object?>{}).entries)
      {'key': 'products.$product.${e.key}', ..._describe(e.value)},
  ];

  if (args.asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'file': path,
        'product': product,
        'schema': doc.schema,
        'signatureChecked': verified != null,
        if (verified != null) 'honoured': _describeLoad(verified),
        'settings': rows,
      }),
    );
    return _ok;
  }

  stdout.writeln('$path → $product (schema ${doc.schema})');
  if (verified == null) {
    stdout.writeln('signature: NOT CHECKED — pass --key to verify it');
  } else {
    stdout
      ..writeln(
        verified.signed
            ? 'signature: VERIFIED against the supplied key'
            : 'signature: none — honoured because it is at the well-known '
                  'location, which only an administrator can write',
      )
      ..writeln(
        'key=${verified.keyStatus.name} '
        'discovery=${verified.discovery.name}',
      );
  }
  stdout.writeln();
  for (final row in rows) {
    final locked = row['locked'] == true ? '  [LOCKED]' : '';
    stdout.writeln('  ${row['key']} = ${jsonEncode(row['value'])}$locked');
  }
  final ignored = doc.products.keys.where((k) => k != product).toList();
  if (ignored.isNotEmpty) {
    final names = ignored.map((k) => 'products.$k').join(', ');
    stdout.writeln('\nignored on this product: $names');
  }
  return _ok;
}

/// The load outcome under the same field names every product's
/// `policy.rejected` / `policy.loaded` record uses.
Map<String, Object?> _describeLoad(PolicyLoadResult result) => {
  if (result.rejection case final rejection?) 'reason': rejection.name,
  'key': result.keyStatus.name,
  'discovery': result.discovery.name,
  'signed': result.signed,
  if (result.detail case final String detail) 'detail': detail,
};

Map<String, Object?> _describe(Object? raw) =>
    raw is Map<String, Object?> && raw.containsKey('value')
    ? {'value': raw['value'], 'locked': raw['locked'] == true}
    : {'value': raw, 'locked': false};

int _init(_Args args) {
  const starter = '''
{
  "schema": 1,
  "org": "Your Organization",

  "suite": {
    "telemetry": "deny",

    "updateChannel": { "value": "pinned", "locked": true },
    "pinnedVersion": "1.0.0"
  },

  "products": {
  }
}
''';
  final out = args.option('--out');
  if (out == null) {
    stdout.write(starter);
  } else {
    try {
      File(out).writeAsStringSync(starter);
    } on FileSystemException catch (error) {
      stderr.writeln('crux-policy: cannot write $out — $error');
      return _ioError;
    }
    stdout.writeln('wrote $out');
  }
  return _ok;
}
