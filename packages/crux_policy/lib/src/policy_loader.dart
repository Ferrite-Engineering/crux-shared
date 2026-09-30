// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_policy/src/policy_document.dart';
import 'package:crux_policy/src/policy_host.dart';
import 'package:crux_signing/crux_signing.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Why a policy file was refused outright.
///
/// Distinct from a *diagnostic*, which reports a key that was skipped inside a
/// file that was otherwise honoured. A rejection discards the whole file.
enum PolicyRejection {
  /// The signature did not verify against the configured public key.
  badSignature,

  /// The file is unsigned and was not found at a trusted path.
  untrustedUnsigned,

  /// The signature envelope itself is malformed.
  malformedSignature,

  /// The file is signed and this machine has no usable organization public
  /// key to check it against.
  ///
  /// Its own reason rather than [badSignature], because the fix is different:
  /// a bad signature means the file or the key is wrong, and this means the
  /// key was never installed (or is unreadable, malformed or writable by every
  /// user — [PolicyLoadResult.keyStatus] says which).
  noPublicKey,

  /// The file is unsigned and sits at the well-known path, but that path is
  /// writable by every user, so it is not the trusted location the design
  /// assumes. *"If any unprivileged user can write it, the policy is not a
  /// control."*
  insecurePath,
}

/// Where the file the loader acted on was found.
///
/// Recorded so that *"which file won"* is answerable without naming the file.
/// **The path itself is deliberately not the answer**: `CRUX_POLICY` can point
/// anywhere, including a home directory, and the suite's audit rule is that no
/// payload carries a filesystem path. The discovery source is the fact an
/// administrator debugging a value they cannot account for actually needs —
/// there are only two places to look, and this says which one won.
enum PolicyDiscovery {
  /// The `CRUX_POLICY` environment variable named an explicit path.
  environmentVariable,

  /// The well-known per-platform path.
  wellKnownPath,

  /// Neither. Every installation with no policy file.
  none,
}

/// What the loader found when it looked for the organization's public key.
///
/// Every value but [configured] means a signed file will be refused with
/// [PolicyRejection.noPublicKey]; the value says what an administrator has to
/// fix, which is the difference between a five-minute ticket and a day-long
/// one.
enum PolicyKeyStatus {
  /// No key: nothing bound in code and no file at the well-known location.
  /// The un-deployed default.
  none,

  /// A 32-byte Ed25519 public key, bound in code or read from the well-known
  /// file.
  configured,

  /// A file exists at the well-known location but does not hold a key in any
  /// accepted encoding.
  malformed,

  /// A file exists at the well-known location but could not be read.
  unreadable,

  /// A file exists but it, or its directory, is writable by every user. A
  /// trust root anyone can replace is not a trust root, so it is ignored.
  insecure,
}

/// The name of the organization's public key file, which lives **beside the
/// policy file at the well-known per-platform location** and nowhere else.
///
/// That placement is the whole design. The policy file may travel — a network
/// share, `CRUX_POLICY` in a pipeline — because the key that vouches for it
/// does not: it is installed once, by an administrator, into the one
/// directory on the machine that needs administrator rights to write. There
/// is deliberately no environment variable for the key path. An env-settable
/// trust root is exactly what an unprivileged process can set, which would
/// let it sign its own policy and point the app at both.
const String kPolicyPublicKeyFileName = 'crux-policy.pub';

/// The organization's Ed25519 public key as the loader resolved it.
///
/// A value rather than a nullable byte list because *why there is no key* is
/// the fact an administrator needs, and `null` cannot carry it.
@immutable
class PolicyPublicKey {
  const PolicyPublicKey._(this.status, this.bytes);

  /// No key anywhere.
  const PolicyPublicKey.none() : this._(PolicyKeyStatus.none, null);

  /// A key file that is not a key.
  const PolicyPublicKey.malformed() : this._(PolicyKeyStatus.malformed, null);

  /// A key file that could not be read.
  const PolicyPublicKey.unreadable() : this._(PolicyKeyStatus.unreadable, null);

  /// A key file writable by every user.
  const PolicyPublicKey.insecure() : this._(PolicyKeyStatus.insecure, null);

  /// The key [bytes] carry, when they are exactly 32 bytes; malformed
  /// otherwise, and none when [bytes] is null. Total: no input throws.
  factory PolicyPublicKey.of(List<int>? bytes) {
    if (bytes == null) return const PolicyPublicKey.none();
    if (bytes.length != 32) return const PolicyPublicKey.malformed();
    return PolicyPublicKey._(
      PolicyKeyStatus.configured,
      List<int>.unmodifiable(bytes),
    );
  }

  /// Parse the contents of a key file.
  ///
  /// Three encodings are accepted, because each is what a different tool
  /// hands an administrator and refusing any of them is a ticket:
  ///
  /// - the **base64** line `crux-policy sign` prints;
  /// - **64 hex characters**;
  /// - a **PEM `PUBLIC KEY` block** — the SubjectPublicKeyInfo form
  ///   `openssl pkey -pubout` writes for Ed25519 (RFC 8410), which is a fixed
  ///   12-byte prefix over the same 32 bytes.
  ///
  /// Blank lines and `#` comment lines are ignored, so an administrator can
  /// label the file. Anything else is [PolicyKeyStatus.malformed]; nothing
  /// throws.
  factory PolicyPublicKey.parse(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .where((line) => !line.startsWith('-----'))
        .toList();
    if (lines.isEmpty) return const PolicyPublicKey.malformed();
    final body = lines.join();

    if (_hex64.hasMatch(body)) {
      return PolicyPublicKey.of(<int>[
        for (var i = 0; i < 64; i += 2)
          int.parse(body.substring(i, i + 2), radix: 16),
      ]);
    }

    final decoded = _decodeLenientBase64(body);
    if (decoded == null) return const PolicyPublicKey.malformed();
    if (decoded.length == 32) return PolicyPublicKey.of(decoded);
    if (decoded.length == _spkiEd25519Prefix.length + 32 &&
        _startsWith(decoded, _spkiEd25519Prefix)) {
      return PolicyPublicKey.of(decoded.sublist(_spkiEd25519Prefix.length));
    }
    return const PolicyPublicKey.malformed();
  }

  /// What was found.
  final PolicyKeyStatus status;

  /// The 32 key bytes, only when [status] is [PolicyKeyStatus.configured].
  final List<int>? bytes;

  static final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// DER `SEQUENCE { SEQUENCE { OID 1.3.101.112 } BIT STRING (0 unused) }`,
  /// the SubjectPublicKeyInfo wrapper RFC 8410 puts around an Ed25519 key.
  static const List<int> _spkiEd25519Prefix = <int>[
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00, //
  ];

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}

/// The outcome of a load.
@immutable
class PolicyLoadResult {
  /// Creates a result.
  const PolicyLoadResult({
    required this.document,
    this.rejection,
    this.sourcePath,
    this.detail,
    this.discovery = PolicyDiscovery.none,
    this.signed = false,
    this.keyStatus = PolicyKeyStatus.none,
  });

  /// The policy in force. [PolicyDocument.absent] when there is none.
  final PolicyDocument document;

  /// Set when a file was found and **refused**.
  final PolicyRejection? rejection;

  /// Where the file came from, when one was read.
  final String? sourcePath;

  /// Developer-facing detail.
  final String? detail;

  /// Where the file was found. [PolicyDiscovery.none] when there was none.
  final PolicyDiscovery discovery;

  /// Whether the file carried a `signature` member.
  ///
  /// **Not the same as "verified"**, and the difference is the point: a
  /// rejected result can be `signed` — that is the ordinary bad-signature case.
  /// Paired with [wasRejected] it answers both halves of the question an
  /// administrator asks, which is *was there a file, and did we trust it*.
  final bool signed;

  /// What the loader found when it looked for the organization's public key.
  ///
  /// Carried on every result, honoured or not, so a settings surface can say
  /// "no key is installed" before a signed file ever arrives.
  final PolicyKeyStatus keyStatus;

  /// Whether a file was found and refused, as opposed to simply absent.
  bool get wasRejected => rejection != null;

  /// Whether a file was found and honoured.
  ///
  /// False both when nothing was found and when something was refused, so a
  /// caller cannot accidentally treat a refusal as a load.
  bool get wasLoaded => rejection == null && discovery != PolicyDiscovery.none;
}

/// Reads, verifies and resolves `.crux-policy.json`.
///
/// ### Discovery order — first hit wins (<https://edacrux.app/policy-reference#where>)
///
/// 1. the `CRUX_POLICY` environment variable
/// 2. the well-known per-platform path
/// 3. absent
///
/// **They are not merged.** Merging two policy files would leave an
/// administrator debugging a value whose source they cannot see.
///
/// ### The two failures that look alike and must not be confused
///
/// - **Missing, unreadable or malformed → absent.** Failing closed here
///   **bricks a deployment** over a typo in an administrator's editor.
/// - **Present but the signature does not verify → refuse the whole file.**
///   Failing open here is **self-granting**, which is the entire reason the
///   file carries a signature.
///
/// ### The trust table
///
/// The organization's public key is read from [kPolicyPublicKeyFileName]
/// beside the well-known policy path — the one directory an unprivileged user
/// cannot write — and from nowhere else. Given that:
///
/// | file | path | key | outcome |
/// |---|---|---|---|
/// | signed, verifies | anywhere | installed | **honoured** |
/// | signed, does not verify | anywhere | installed | `badSignature` |
/// | signed | anywhere | none | `noPublicKey` |
/// | unsigned | well-known | any | **honoured** |
/// | unsigned | `CRUX_POLICY` | any | `untrustedUnsigned` |
///
/// The key's presence never widens what an unsigned file may do. An earlier
/// revision honoured an unsigned `CRUX_POLICY` file when no key was configured,
/// as an "un-deployed default" — which was exactly the attack the signature
/// exists to prevent, since the un-deployed default is every machine and
/// `CRUX_POLICY` is what an unprivileged process can set.
///
/// The threat model, stated once: the file arrives from a network share an
/// attacker may be able to write to. That is what the signature is for.
class PolicyLoader {
  /// Creates a loader.
  ///
  /// [trustedPublicKey] binds the **organization's own** Ed25519 public key in
  /// code — the `crux-policy inspect --key` seam, and a test's. Production
  /// leaves it null, and the loader reads the key from
  /// [effectivePublicKeyPath] instead. Ferrite holds no key here and must
  /// never appear to.
  ///
  /// [publicKeyPath] overrides where that file is looked for, for tests. When
  /// neither it nor [wellKnownPath] is given the key is
  /// [defaultPublicKeyPath]; when only [wellKnownPath] is given the key is
  /// the file of the same name beside it, so a test that redirects the policy
  /// directory redirects both.
  const PolicyLoader({
    this.trustedPublicKey,
    this.publicKeyPath,
    this.environment,
    this.wellKnownPath,
  });

  /// The organization's public verify key bound in code, or null to read it
  /// from [effectivePublicKeyPath], which is what production does.
  final List<int>? trustedPublicKey;

  /// Overrides where the public key file is read from, for tests.
  final String? publicKeyPath;

  /// Environment overrides, for tests. Defaults to the real environment.
  final Map<String, String>? environment;

  /// Overrides the per-platform well-known path, for tests.
  final String? wellKnownPath;

  /// The name of the policy file at the well-known location.
  static const String policyFileName = '.crux-policy.json';

  /// The well-known per-platform directory that holds the policy file and the
  /// organization's public key (<https://edacrux.app/policy-reference#where>).
  ///
  /// Safe to call on a host without `dart:io`: a browser has no well-known
  /// location, so it gets the generic path, which cannot exist there.
  static String defaultWellKnownDirectory({String? operatingSystem}) {
    final os = operatingSystem ?? hostOperatingSystem();
    return switch (os) {
      'macos' => '/Library/Application Support/EDACrux',
      'windows' => p.windows.join(
        _environmentValue(null, 'ProgramData') ?? r'C:\ProgramData',
        'EDACrux',
      ),
      _ => '/etc/edacrux',
    };
  }

  /// The well-known per-platform policy file.
  static String defaultWellKnownPath({String? operatingSystem}) {
    final os = operatingSystem ?? hostOperatingSystem();
    return _pathsFor(os).join(
      defaultWellKnownDirectory(operatingSystem: os),
      policyFileName,
    );
  }

  /// The well-known per-platform public key file: [kPolicyPublicKeyFileName]
  /// in the same directory as the policy file.
  static String defaultPublicKeyPath({String? operatingSystem}) {
    final os = operatingSystem ?? hostOperatingSystem();
    return _pathsFor(os).join(
      defaultWellKnownDirectory(operatingSystem: os),
      kPolicyPublicKeyFileName,
    );
  }

  /// Path rules for [os], not for the host. On the host itself the two are
  /// the same; they differ when one platform describes another, which is what
  /// `crux-policy sign` does when it names all three install locations — and
  /// a Mac printing `C:\ProgramData/EDACrux/…` is naming a file that exists
  /// nowhere.
  static p.Context _pathsFor(String os) =>
      os == 'windows' ? p.windows : p.posix;

  /// Where this loader reads the organization's public key from.
  ///
  /// Never from the environment. See [kPolicyPublicKeyFileName].
  String get effectivePublicKeyPath {
    final explicit = publicKeyPath;
    if (explicit != null) return explicit;
    final policy = wellKnownPath;
    if (policy != null) {
      return p.join(p.dirname(policy), kPolicyPublicKeyFileName);
    }
    return defaultPublicKeyPath();
  }

  /// Load the policy in force. **Never throws** — including on a host with no
  /// process environment or filesystem, such as a browser, where the answer is
  /// absent.
  PolicyLoadResult load() {
    final key = _resolvePublicKey();

    final explicit = _environmentValue(environment, 'CRUX_POLICY');
    if (explicit != null && explicit.trim().isNotEmpty) {
      return _read(
        explicit.trim(),
        trustedPath: false,
        discovery: PolicyDiscovery.environmentVariable,
        key: key,
      );
    }

    final wellKnown = wellKnownPath ?? defaultWellKnownPath();
    // The well-known path is trusted BECAUSE it needs administrator rights to
    // write. A directory somebody created world-writable has lost that
    // property, and a loader that kept trusting it would be trusting a name.
    final insecure = _isWorldWritable(wellKnown);
    return _read(
      wellKnown,
      trustedPath: !insecure,
      insecurePath: insecure,
      discovery: PolicyDiscovery.wellKnownPath,
      key: key,
    );
  }

  /// The organization's public key: bound in code, else read from
  /// [effectivePublicKeyPath]. Never throws.
  PolicyPublicKey _resolvePublicKey() {
    final bound = trustedPublicKey;
    if (bound != null) return PolicyPublicKey.of(bound);

    final path = effectivePublicKeyPath;
    try {
      if (!hostFileExists(path)) return const PolicyPublicKey.none();
      if (_isWorldWritable(path)) return const PolicyPublicKey.insecure();
      return PolicyPublicKey.parse(hostReadFile(path));
    } on Object {
      return const PolicyPublicKey.unreadable();
    }
  }

  /// Whether [path] or the directory holding it is writable by every user.
  ///
  /// Both, because a world-writable directory lets anyone replace a file they
  /// cannot write. Only meaningful on POSIX hosts; elsewhere the host answers
  /// false and the installer's ACL is the control.
  static bool _isWorldWritable(String path) =>
      hostIsWorldWritable(path) || hostIsWorldWritable(p.dirname(path));

  /// Reads [name] from [environment], or from the host's when null.
  ///
  /// A host that cannot provide an environment at all has no override in it,
  /// which is the same answer as a variable that is unset.
  static String? _environmentValue(
    Map<String, String>? environment,
    String name,
  ) {
    try {
      return (environment ?? hostEnvironment())[name];
    } on Object {
      return null;
    }
  }

  PolicyLoadResult _read(
    String path, {
    required bool trustedPath,
    required PolicyDiscovery discovery,
    required PolicyPublicKey key,
    bool insecurePath = false,
  }) {
    final String source;
    try {
      if (!hostFileExists(path)) {
        // Absent, NOT rejected. A CRUX_POLICY pointing at nothing is a
        // deployment that has not landed yet, not an attack — and a missing
        // file at the well-known path is the ordinary un-deployed machine.
        //
        // `discovery` stays `none`: nothing was found, and reporting the
        // variable as the source of a file that does not exist would make
        // "which file won" answer with one that never did.
        return PolicyLoadResult(
          document: PolicyDocument.absent,
          keyStatus: key.status,
        );
      }
      source = hostReadFile(path);
    } on Object {
      // Unreadable is absent, for the same reason.
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        keyStatus: key.status,
      );
    }

    return verify(
      source,
      path: path,
      trustedPath: trustedPath,
      insecurePath: insecurePath,
      discovery: discovery,
      key: key,
    );
  }

  /// Verify [source] and parse it. Exposed for the CLI and for tests.
  ///
  /// Pure: it touches no file. The [key] is whatever the caller resolved —
  /// [load] passes the well-known file's — and defaults to the key bound in
  /// code, or none. [insecurePath] marks a well-known path that turned out to
  /// be world-writable; it only matters when [trustedPath] is false and the
  /// file is unsigned, where it names the right fix.
  PolicyLoadResult verify(
    String source, {
    required String path,
    required bool trustedPath,
    PolicyDiscovery discovery = PolicyDiscovery.wellKnownPath,
    bool insecurePath = false,
    PolicyPublicKey? key,
  }) {
    final resolvedKey = key ?? PolicyPublicKey.of(trustedPublicKey);
    final keyStatus = resolvedKey.status;

    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      // Malformed is absent, not rejected: it is far more likely to be a typo
      // in an administrator's editor than an attack, and an attacker who can
      // write the file can write valid JSON.
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        keyStatus: keyStatus,
      );
    }
    if (decoded is! Map<String, Object?>) {
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        keyStatus: keyStatus,
      );
    }

    final signature = decoded['signature'];

    if (signature == null) {
      // Unsigned. Honoured ONLY from a trusted path — the well-known
      // per-platform location, which needs administrator rights to write.
      // Whether a key is installed does not enter into it: a key widens what
      // a SIGNED file may do, never what an unsigned one may.
      if (trustedPath) {
        return PolicyLoadResult(
          document: PolicyDocument.parse(source),
          sourcePath: path,
          discovery: discovery,
          keyStatus: keyStatus,
        );
      }
      if (insecurePath) {
        return PolicyLoadResult(
          document: PolicyDocument.absent,
          rejection: PolicyRejection.insecurePath,
          sourcePath: path,
          discovery: discovery,
          keyStatus: keyStatus,
          detail:
              'the well-known policy location is writable by every user, so '
              'an unsigned file there is not a control; restrict it to '
              'administrators, or sign the file',
        );
      }
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        rejection: PolicyRejection.untrustedUnsigned,
        sourcePath: path,
        discovery: discovery,
        keyStatus: keyStatus,
        detail:
            'unsigned policy file outside a trusted path; sign it, or install '
            'it at the well-known location',
      );
    }

    if (signature is! String) {
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        rejection: PolicyRejection.malformedSignature,
        sourcePath: path,
        discovery: discovery,
        signed: true,
        keyStatus: keyStatus,
        detail: '"signature" must be a base64 string',
      );
    }

    final keyBytes = resolvedKey.bytes;
    if (keyBytes == null) {
      // Signed, but nothing to check it against. Refuse rather than honour: a
      // signed file whose signature nobody verifies is strictly worse than an
      // unsigned one, because it LOOKS verified. The detail names the fix,
      // because "no key" has four different causes with four different fixes.
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        rejection: PolicyRejection.noPublicKey,
        sourcePath: path,
        discovery: discovery,
        signed: true,
        keyStatus: keyStatus,
        detail: switch (keyStatus) {
          PolicyKeyStatus.malformed =>
            'the file is signed but the installed public key file is not a '
                '32-byte Ed25519 public key (base64, hex or PEM)',
          PolicyKeyStatus.unreadable =>
            'the file is signed but the installed public key file cannot be '
                'read',
          PolicyKeyStatus.insecure =>
            'the file is signed but the installed public key file is writable '
                'by every user and cannot be trusted; restrict it to '
                'administrators',
          PolicyKeyStatus.none || PolicyKeyStatus.configured =>
            'the file is signed but no organization public key is installed; '
                'install it as $kPolicyPublicKeyFileName beside the '
                'well-known policy file',
        },
      );
    }

    final signatureBytes = _decodeLenientBase64(signature);
    if (signatureBytes == null || signatureBytes.length != 64) {
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        rejection: PolicyRejection.malformedSignature,
        sourcePath: path,
        discovery: discovery,
        signed: true,
        keyStatus: keyStatus,
        detail: 'signature is not 64 bytes of base64',
      );
    }

    final message = utf8.encode(canonicalPayload(decoded));
    if (!ed25519Verify(
      message: message,
      signature: signatureBytes,
      publicKey: keyBytes,
    )) {
      return PolicyLoadResult(
        document: PolicyDocument.absent,
        rejection: PolicyRejection.badSignature,
        sourcePath: path,
        discovery: discovery,
        signed: true,
        keyStatus: keyStatus,
        detail: 'signature does not verify against the installed key',
      );
    }

    return PolicyLoadResult(
      document: PolicyDocument.parse(source),
      sourcePath: path,
      discovery: discovery,
      signed: true,
      keyStatus: keyStatus,
    );
  }

  /// The exact bytes a signature is taken over: the document with `signature`
  /// removed, re-encoded with **sorted keys**.
  ///
  /// Sorting is what makes the signature independent of how an administrator's
  /// editor happened to order the file — the same property Keygen buys by
  /// signing the *encoded* form of a licence payload. Without it, reformatting
  /// a policy file in an editor would silently invalidate its signature and the
  /// failure would look like tampering.
  static String canonicalPayload(Map<String, Object?> document) {
    final withoutSignature = <String, Object?>{
      for (final entry in document.entries)
        if (entry.key != 'signature') entry.key: entry.value,
    };
    return jsonEncode(_sorted(withoutSignature));
  }

  static Object? _sorted(Object? value) {
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return <String, Object?>{for (final k in keys) k: _sorted(value[k])};
    }
    if (value is List<Object?>) return value.map(_sorted).toList();
    return value;
  }
}

/// Base64 the way a human writes it: whitespace anywhere, either alphabet,
/// padding optional. Null when it is not base64 at all.
///
/// One decoder for the signature and the public key, library-private to both:
/// a second lenient decoder would eventually accept a different set of
/// inputs, and "the key file parses but the signature does not" is a ticket
/// nobody should get.
List<int>? _decodeLenientBase64(String input) {
  var text = input.replaceAll(RegExp(r'\s'), '');
  if (text.isEmpty) return null;
  text = text.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = text.length % 4;
  if (remainder == 1) return null;
  if (remainder != 0) {
    text = text.padRight(text.length + (4 - remainder), '=');
  }
  try {
    return base64.decode(text);
  } on FormatException {
    return null;
  }
}
