// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Pure Dart only: this file is on the `crux_license_core.dart` barrel, which
// the products' headless CLIs link without `dart:ui`, and
// `test/crux_license_core_test.dart` walks that barrel's closure.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crux_io/crux_io.dart';
import 'package:path/path.dart' as p;

/// Mints an install fingerprint: sixteen random bytes, base64url, unpadded.
///
/// Minted, not derived. A fingerprint computed from the hostname or the
/// hardware changes when a user renames their laptop and silently burns a
/// seat; a random value identifies exactly what the issuer needs it to — this
/// machine — and nothing about the person running it. Every product and every
/// headless run mints through this, so a fingerprint has one shape wherever
/// it was created. The shape is URL-safe, which is what lets a fingerprint
/// stand in for the machine's id on the issuer's machine endpoints.
String mintInstallFingerprint([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The suite's shared licence directory: where the machine fingerprint and
/// the release marker live, for every product on this account.
///
/// - **macOS**: `$HOME/Library/Application Support/crux/license`
/// - **Windows**: `%LOCALAPPDATA%\crux\license`
/// - **Linux / other POSIX**:
///   `${XDG_DATA_HOME:-$HOME/.local/share}/crux/license`
///
/// Derived from the environment rather than from `path_provider`, because a
/// `dart build cli` binary cannot load a plugin and must resolve the same
/// directory the desktop app does. The `crux/` parent is the suite's shared
/// application-data root.
///
/// ### Why `%LOCALAPPDATA%` and not `%APPDATA%`
///
/// Roaming AppData follows a user to every computer they sign in to under a
/// roaming profile. A machine identity that roams is not a machine identity:
/// two computers would present one fingerprint, hold one seat between them
/// and share one machine record at the issuer, and the seat count the licence
/// sells would count users, not machines. Local AppData stays on the machine
/// it was written on. The per-product files this directory replaces lived in
/// `%APPDATA%`; [legacyInstallFingerprintPath] still looks for them there,
/// but only to read them.
///
/// [environment] and [operatingSystem] are injectable for tests. Throws
/// [StateError] when the variable the platform needs is unset; callers treat
/// that as "no shared directory".
String cruxLicenseDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) => _licenseDirectory(
  environment: environment,
  operatingSystem: operatingSystem,
  roaming: false,
);

/// Where [product] kept its own fingerprint file before the fingerprint was
/// shared: `<base>/crux/license/<product>.fingerprint`, with `<base>` as in
/// [cruxLicenseDirectory] except on Windows, where it is `%APPDATA%`, which
/// is where those files were written.
///
/// Read as a migration source only — see [SharedInstallFingerprint] — and
/// never written. [product] is the lower-case product slug (`lintcrux`,
/// `simcrux`); anything outside `[a-z0-9_]` is an [ArgumentError], because
/// the slug becomes a file name.
String legacyInstallFingerprintPath(
  String product, {
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  _requireProductSlug(product);
  final os = operatingSystem ?? Platform.operatingSystem;
  return _contextFor(os).join(
    _licenseDirectory(
      environment: environment,
      operatingSystem: os,
      roaming: true,
    ),
    '$product.fingerprint',
  );
}

/// This machine's licence fingerprint, in a plain file every product on this
/// account reads and writes.
///
/// ### Why a file, and not the credential store
///
/// A suite licence's seat count counts machines, and the fingerprint is what
/// the issuer counts them by, so all four products on one computer must
/// present the same one. The OS credential store cannot hold a value four
/// applications share: a macOS keychain item is ACL'd to the application that
/// created it and a read from another prompts the user; Windows keeps the
/// suite's secrets in a per-application DPAPI store; libsecret keys its
/// schema by application id. Each product would read its own copy — which is
/// the per-install fingerprint this replaces, the one that made four products
/// on one computer look like four machines and exhausted a three-seat suite
/// licence at the third product. A file under the suite's shared data
/// directory has no owner but the user.
///
/// The fingerprint is not a secret, so a plain file loses nothing: the issuer
/// holds it, the offline activation request carries it in plain text, and a
/// machine file names it in its signed payload. What the credential store is
/// for — the licence key, the machine id, the issuer's last answer — stays
/// there, per product.
///
/// A headless run needs the file for an older reason too: the credential
/// store is a Flutter plugin the CLI binary cannot link, and on a build agent
/// it is locked, missing, or answers only with a prompt nobody is there to
/// click.
///
/// Every method fails soft. A file that cannot be read or written reads as
/// "no fingerprint", and the product's store falls back to a fingerprint of
/// its own so licensing keeps working on a broken profile.
class InstallFingerprintFile {
  /// A file at the path [resolvePath] returns, resolved on every access so a
  /// missing home directory is a failed read rather than a failed constructor.
  InstallFingerprintFile(String Function() resolvePath)
    : _resolvePath = resolvePath;

  /// The suite's shared file, `install.fingerprint` under
  /// [cruxLicenseDirectory] for [environment] and [operatingSystem].
  factory InstallFingerprintFile.shared({
    Map<String, String>? environment,
    String? operatingSystem,
  }) => InstallFingerprintFile(() {
    final os = operatingSystem ?? Platform.operatingSystem;
    return _contextFor(os).join(
      cruxLicenseDirectory(environment: environment, operatingSystem: os),
      'install.fingerprint',
    );
  });

  /// The file [product] wrote before the fingerprint was shared, at
  /// [legacyInstallFingerprintPath]. A migration source: read it, never
  /// [publish] to it.
  factory InstallFingerprintFile.legacy(
    String product, {
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    // Checked here as well as in the path builder: the builder runs inside
    // the fail-soft read, where a bad slug would read as "no fingerprint"
    // instead of failing the caller that wrote it.
    _requireProductSlug(product);
    return InstallFingerprintFile(
      () => legacyInstallFingerprintPath(
        product,
        environment: environment,
        operatingSystem: operatingSystem,
      ),
    );
  }

  final String Function() _resolvePath;

  /// The recorded fingerprint, or `null` when there is none or it cannot be
  /// read.
  Future<String?> read() async {
    try {
      final file = File(_resolvePath());
      if (!file.existsSync()) return null;
      return _accept(await file.readAsString());
    } on Object {
      return null;
    }
  }

  /// The recorded fingerprint, minting and recording one when there is none.
  ///
  /// `null` only when the file can be neither read nor written.
  Future<String?> readOrCreate() async {
    final existing = await read();
    if (existing != null) return existing;
    try {
      await _write(mintInstallFingerprint());
    } on Object {
      return null;
    }
    // Read back rather than returning the value just minted: two first runs
    // racing on one machine each mint, the last rename wins, and both then
    // use the one that stuck.
    return read();
  }

  /// Records [candidate] unless a fingerprint is already recorded, and
  /// returns whichever value the file holds afterwards.
  ///
  /// This is the migration step. A product that finds no shared fingerprint
  /// but still has its own offers it here, so an activation made before the
  /// fingerprint was shared keeps the identity the issuer already counts a
  /// machine under, rather than minting a fresh one and taking a second seat.
  /// Two products migrating at once each offer their own value; the last
  /// rename wins, and both read back the one that stuck, which is what makes
  /// them converge.
  ///
  /// `null` when [candidate] is not a fingerprint, or the file can be neither
  /// read nor written.
  Future<String?> adopt(String candidate) async {
    final value = _accept(candidate);
    if (value == null) return null;
    final existing = await read();
    if (existing != null) return existing;
    try {
      await _write(value);
    } on Object {
      return null;
    }
    return read();
  }

  /// Records [fingerprint], replacing whatever was recorded before.
  ///
  /// Never throws. A fingerprint that cannot be published leaves a headless
  /// run refusing a machine file; it must not take the desktop app's licence
  /// flow down with it.
  Future<void> publish(String fingerprint) async {
    final value = _accept(fingerprint);
    if (value == null) return;
    try {
      if (await read() == value) return;
      await _write(value);
    } on Object {
      // See the method doc: publishing is best effort.
    }
  }

  // Written beside the target and renamed over it, so a concurrent reader
  // sees the old fingerprint or the new one, never a torn line. Durable, not
  // ephemeral: a fingerprint lost to a crash is a seat burned at the issuer,
  // and nothing republishes it on a timer.
  Future<void> _write(String value) =>
      writeStringAtomic(File(_resolvePath()), '$value\n');
}

/// Where a product's licence store gets the machine fingerprint from.
///
/// An interface so that no test can reach the developer's real shared file:
/// the product's store takes one as a required parameter, production passes
/// [SharedInstallFingerprint], and a test passes
/// [InMemoryInstallFingerprintSource]. One method, deliberately — the seam is
/// the point, not the method count.
// ignore: one_member_abstracts
abstract class InstallFingerprintSource {
  /// The machine's fingerprint, created when there is none.
  ///
  /// [legacy] names where an earlier release of the product may have kept a
  /// fingerprint of its own, in the order they should be tried. The first one
  /// that yields a fingerprint is adopted rather than a fresh one minted, so
  /// an activation the issuer already holds a machine for keeps its identity.
  /// A legacy reader that throws is not a reader that answered "none": the
  /// exception propagates, because minting past a store that is merely locked
  /// would burn the seat the store was protecting.
  ///
  /// `null` when no fingerprint can be kept, in which case the caller falls
  /// back to a fingerprint of its own.
  Future<String?> readOrCreate({
    Iterable<Future<String?> Function()> legacy = const [],
  });
}

/// The one fingerprint every product on this machine presents to the issuer.
///
/// Resolution, first hit wins:
///
/// 1. The shared file.
/// 2. The `legacy` sources, in the order given — a product passes its own
///    credential-store entry first, then the per-product files earlier
///    releases wrote — the first of which that yields a fingerprint is
///    adopted into the shared file. This is what keeps an upgrade from
///    burning seats: an install that activated before the fingerprint was
///    shared keeps the identity the issuer already holds a machine for. Every
///    product lists the files in the same order, so two products upgrading on
///    one machine converge on the same value whichever runs first.
/// 3. Mint one, and record it.
///
/// Whichever is chosen is read back from the file rather than returned from
/// memory, so two products racing this on one machine end up with the value
/// that stuck. Legacy entries are left where they are, so a downgrade still
/// finds its fingerprint.
///
/// `null` only when the shared file can be neither read nor written; the
/// caller then falls back to a fingerprint of its own, so a broken profile
/// costs a seat and not a licence.
class SharedInstallFingerprint implements InstallFingerprintSource {
  /// Over [file], which defaults to [InstallFingerprintFile.shared] for
  /// [environment] and [operatingSystem].
  SharedInstallFingerprint({
    InstallFingerprintFile? file,
    Map<String, String>? environment,
    String? operatingSystem,
  }) : _file =
           file ??
           InstallFingerprintFile.shared(
             environment: environment,
             operatingSystem: operatingSystem,
           );

  final InstallFingerprintFile _file;

  @override
  Future<String?> readOrCreate({
    Iterable<Future<String?> Function()> legacy = const [],
  }) async {
    final existing = await _file.read();
    if (existing != null) return existing;
    for (final source in legacy) {
      final candidate = await source();
      if (candidate == null) continue;
      final adopted = await _file.adopt(candidate);
      if (adopted != null) return adopted;
      // Not a fingerprint, or the file is unwritable. The next source may
      // hold a real one; if the file is the problem, minting fails the same
      // way and the caller hears `null` from there.
    }
    return _file.readOrCreate();
  }
}

/// An [InstallFingerprintSource] that never touches disk, for tests.
///
/// Holds one [value], honours `legacy` the way [SharedInstallFingerprint]
/// does, and mints when it has nothing. Construct it [usable] `false` to play
/// the broken profile — every call answers `null`, and the store under test
/// has to fall back.
class InMemoryInstallFingerprintSource implements InstallFingerprintSource {
  /// Create one holding [value], or nothing.
  InMemoryInstallFingerprintSource({this.value, this.usable = true});

  /// The fingerprint held, or `null` until one is adopted or minted.
  String? value;

  /// Whether the source can keep a fingerprint at all.
  final bool usable;

  @override
  Future<String?> readOrCreate({
    Iterable<Future<String?> Function()> legacy = const [],
  }) async {
    if (!usable) return null;
    final existing = value;
    if (existing != null) return existing;
    for (final source in legacy) {
      final candidate = _accept(await source() ?? '');
      if (candidate != null) return value = candidate;
    }
    return value = mintInstallFingerprint();
  }
}

/// [raw] trimmed when it has the shape [mintInstallFingerprint] produces,
/// else `null` — a hand-edited or truncated file is no fingerprint at all.
String? _accept(String raw) {
  final value = raw.trim();
  return _shape.hasMatch(value) ? value : null;
}

final RegExp _shape = RegExp(r'^[A-Za-z0-9_-]{16,256}$');

final RegExp _productSlug = RegExp(r'^[a-z0-9_]+$');

void _requireProductSlug(String product) {
  if (!_productSlug.hasMatch(product)) {
    throw ArgumentError.value(
      product,
      'product',
      'must match [a-z0-9_]+; it becomes a file name',
    );
  }
}

/// Join in the style of the OS being asked about, not the host's: a test
/// that passes `operatingSystem: 'windows'` on a macOS runner wants
/// backslashes.
p.Context _contextFor(String operatingSystem) =>
    operatingSystem == 'windows' ? p.windows : p.posix;

/// `<base>/crux/license`, where `<base>` is the platform's per-user data
/// directory — the roaming one on Windows when [roaming], for the legacy
/// files, and the local one otherwise.
String _licenseDirectory({
  required bool roaming,
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;

  String requireEnv(String name) {
    final value = env[name];
    if (value == null || value.isEmpty) {
      throw StateError(
        'cruxLicenseDirectory: \$$name is not set; cannot resolve the '
        'shared licence directory',
      );
    }
    return value;
  }

  final ctx = _contextFor(os);
  final String base;
  switch (os) {
    case 'macos':
      base = ctx.join(requireEnv('HOME'), 'Library', 'Application Support');
    case 'windows':
      base = requireEnv(roaming ? 'APPDATA' : 'LOCALAPPDATA');
    default:
      final xdg = env['XDG_DATA_HOME'];
      base = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : ctx.join(requireEnv('HOME'), '.local', 'share');
  }
  return ctx.join(base, 'crux', 'license');
}
