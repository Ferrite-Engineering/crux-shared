// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_license/src/install_fingerprint.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/owner_only_file.dart';
import 'package:path/path.dart' as p;

/// Whether [credential] may be kept in a [LicenseFallbackFile] when the
/// operating system's credential store cannot keep it: a licence file or a
/// machine file, the signed offline forms, and nothing else.
///
/// A licence **key** never may. It is a bearer credential that the issuer
/// answers for wherever it is presented, and keeping one in a file would be a
/// plaintext copy of exactly what the credential store exists to protect. A
/// machine file works only on the machine whose fingerprint it names, and a
/// licence file carries its own signed term and entitlements; both are
/// checked offline, and the user chose to download them as files in the
/// first place.
bool licenseCredentialMayUseFallbackFile(String credential) =>
    switch (parseLicenseCredential(credential).envelope?.kind) {
      LicenseCredentialKind.licenseFile ||
      LicenseCredentialKind.machineFile => true,
      LicenseCredentialKind.licenseKey || null => false,
    };

/// Where [product] keeps its licence when the operating system's credential
/// store cannot: `<product>.license` in [cruxLicenseDirectory], beside the
/// machine's `install.fingerprint`.
///
/// Per product, like the credential store it stands in for. [product] is the
/// lower-case product slug (`netcrux`); anything outside `[a-z0-9_]` is an
/// [ArgumentError], because the slug becomes a file name. Throws
/// [StateError] when the directory cannot be resolved, as
/// [cruxLicenseDirectory] does.
String licenseFallbackFilePath(
  String product, {
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(product)) {
    throw ArgumentError.value(
      product,
      'product',
      'must match [a-z0-9_]+; it becomes a file name',
    );
  }
  final os = operatingSystem ?? Platform.operatingSystem;
  final context = os == 'windows' ? p.windows : p.posix;
  return context.join(
    cruxLicenseDirectory(environment: environment, operatingSystem: os),
    '$product.license',
  );
}

/// A file only its owner can read, holding a product's licence when the
/// operating system's credential store is unavailable.
///
/// ### Why a licence may fall back to a file
///
/// On Linux the credential store is libsecret, which needs a secret service
/// running in the user's session. Remote X sessions, shared login hosts and
/// minimal installs often have none, and every call then fails. A licence
/// that can only be kept there cannot be activated on those machines at all.
///
/// `crux_secrets` keeps refusing to degrade to a file, and that stays right
/// for API keys and passwords. This is a decision about licences alone, and
/// only about the offline forms ([licenseCredentialMayUseFallbackFile]): a
/// licence file or a machine file is signed, checked offline, names its own
/// expiry, and a machine file works only on the machine it names.
/// `CruxLicenseController` decides when to use this file, when the product's
/// store refuses one of those; this class only keeps it.
///
/// ### Owner-only from the first byte
///
/// On macOS and Linux the contents are written into a scratch file that the
/// C library's `mkstemp` created with mode `0600`, then renamed over the
/// target, which keeps that mode. The file never exists
/// with a wider mode, not even empty. Where no such file can be created the
/// write fails rather than falling back to a default mode. On Windows the
/// file is written atomically into `%LOCALAPPDATA%`, whose access-control
/// list admits only the user.
class LicenseFallbackFile {
  /// A file at the path [resolvePath] returns, resolved on every access so a
  /// missing home directory is a failed operation rather than a failed
  /// constructor.
  LicenseFallbackFile(String Function() resolvePath)
    : _resolvePath = resolvePath;

  /// [product]'s file, at [licenseFallbackFilePath].
  factory LicenseFallbackFile.forProduct(
    String product, {
    Map<String, String>? environment,
    String? operatingSystem,
  }) => LicenseFallbackFile(
    () => licenseFallbackFilePath(
      product,
      environment: environment,
      operatingSystem: operatingSystem,
    ),
  );

  final String Function() _resolvePath;

  /// The file's path, or `null` when it cannot be resolved.
  String? get path {
    try {
      return _resolvePath();
    } on Object {
      return null;
    }
  }

  /// The file's contents, or `null` when there is no file or it cannot be
  /// read.
  Future<String?> read() async {
    try {
      final file = File(_resolvePath());
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } on Object {
      return null;
    }
  }

  /// Whether the file exists.
  bool exists() {
    final at = path;
    return at != null && File(at).existsSync();
  }

  /// Replaces the file with [contents], atomically and owner-only.
  ///
  /// Throws when the file cannot be written, and on macOS and Linux when no
  /// owner-only file can be created; a licence is never written to a file
  /// with a wider mode.
  Future<void> write(String contents) async {
    final target = _resolvePath();
    await Directory(p.dirname(target)).create(recursive: true);
    if (Platform.isWindows) {
      await writeStringAtomic(File(target), contents);
      return;
    }
    final scratchPath = createOwnerOnlyScratchFile(target);
    if (scratchPath == null) {
      throw FileSystemException(
        'cannot create a file only its owner can read',
        target,
      );
    }
    final scratch = File(scratchPath);
    try {
      // `mkstemp` promises 0600. Checked anyway, before the licence is in it,
      // because a C library that broke that promise would otherwise be found
      // out only by somebody else reading the file.
      if (scratch.statSync().mode & _groupOrOtherBits != 0) {
        throw FileSystemException('scratch file is not owner-only', target);
      }
      await scratch.writeAsString(contents, flush: true);
      await scratch.rename(target);
    } on Object {
      try {
        if (scratch.existsSync()) scratch.deleteSync();
      } on FileSystemException {
        // The write failure is the error the caller needs to see.
      }
      rethrow;
    }
  }

  /// Removes the file. `true` when there was one.
  ///
  /// Throws when a file exists and cannot be removed: a licence the user
  /// asked to forget must not stay behind quietly.
  Future<bool> delete() async {
    final file = File(_resolvePath());
    if (!file.existsSync()) return false;
    await file.delete();
    return true;
  }
}

/// The group and other permission bits.
const int _groupOrOtherBits = 0x3f;
