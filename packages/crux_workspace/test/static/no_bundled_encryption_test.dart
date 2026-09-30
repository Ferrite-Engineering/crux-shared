// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// crux-shared's copy of the suite's export-control guard.
///
/// The suite's export-control position answers "which products implement
/// encryption?" with *WaveCrux Pro only*, and explicitly includes "nor in any
/// `crux-shared` package" in the negative half. Each product tests its own
/// half. **crux-shared did not**, and the gap was found the hard way: the
/// licence validator was first written against
/// `package:cryptography`, which ships AES-GCM and ChaCha20, and it reached all
/// four products and the open-core tree before a product's guard caught it.
///
/// Two things ride on the claim:
///
/// 1. **The App Store declaration.** Open core's
///    `ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption` as
///    `false`. A cipher arriving here reaches open core, and the declaration
///    becomes untrue.
/// 2. **The open-core flip.** Publishing encryption *source code* triggers an
///    EAR §742.15(b) notification obligation that publishing TLS-calling code
///    does not. Every package here is published at the flip.
///
/// crux-shared is where a cipher would do the most damage and where it was
/// least likely to be noticed — one dependency line, eight repositories.
///
/// **Signature verification is not encryption.** `crux_signing` implements
/// Ed25519 *verification* by hand
/// (`packages/crux_signing/lib/src/ed25519.dart`) precisely so that no cipher
/// is needed: it hashes with `package:crypto` and does elliptic-curve
/// arithmetic, and there is no symmetric algorithm, key agreement, or key
/// generation anywhere in it. Hashing stays allowed for the same reason it does
/// in the product guards.
///
/// If a cipher genuinely belongs here, the export-control position is what
/// needs revisiting first — do not simply delete an entry from the list below.
void main() {
  test('no crux-shared package resolves an encryption implementation', () {
    final lock = File(p.join(_workspaceRoot(), 'pubspec.lock'));
    expect(
      lock.existsSync(),
      isTrue,
      reason:
          'the melos workspace lock is missing, so this guard cannot see the '
          'resolved dependency set',
    );

    final resolved = _resolvedPackages(lock.readAsStringSync());
    final found = _encryptionPackages.where(resolved.contains).toList();

    expect(
      found,
      isEmpty,
      reason:
          'crux-shared resolved an encryption package: ${found.join(', ')}.\n\n'
          'Every package here ships into all four products and is published at '
          'the open-core flip, so a cipher landing in crux-shared contradicts '
          "the suite's export-control position, makes open core's "
          'ITSAppUsesNonExemptEncryption=false declaration untrue, and '
          'acquires an EAR §742.15(b) notification obligation.\n\n'
          'This fires for transitive pull-ups too, which is the case nothing '
          'else would catch. Run `dart pub deps` to find who wants it.',
    );
  });

  test('the guard is not vacuous', () {
    // The list means nothing if the lock is not actually being read. `crypto`
    // is resolved here (crux_license hashes with it) and is deliberately NOT
    // on the banned list, which makes it the right probe: it proves the parse
    // works without weakening the assertion above.
    final lock = File(p.join(_workspaceRoot(), 'pubspec.lock'));
    final resolved = _resolvedPackages(lock.readAsStringSync());
    expect(resolved, contains('crypto'), reason: 'the lock did not parse');
    expect(resolved.length, greaterThan(20));
  });
}

/// Packages that implement a cipher, as opposed to hashing or calling the
/// platform's TLS.
///
/// Kept byte-identical to the four products' copies on purpose: a per-repo list
/// that drifts is a per-repo answer to a suite-wide question.
const _encryptionPackages = <String>{
  'cryptography',
  'cryptography_flutter',
  'cryptography_flutter_plus',
  'cryptography_plus',
  'encrypt',
  'flutter_sodium',
  'libsodium',
  'pointycastle',
  'sodium',
  'sodium_libs',
  'steel_crypt',
  'webcrypto',
};

Set<String> _resolvedPackages(String lock) => RegExp(
  r'^  ([a-z_0-9]+):$',
  multiLine: true,
).allMatches(lock).map((m) => m.group(1)!).toSet();

String _workspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: crux_shared_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate the crux-shared workspace root from '
    '${Directory.current.path}',
  );
}
