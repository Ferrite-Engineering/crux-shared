// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How `crux-policy inspect --key` decides what a product would do with a
/// file. Used by the CLI only; not exported from the package barrel.
library;

import 'package:crux_policy/src/policy_loader.dart';
import 'package:path/path.dart' as p;

/// A loader that answers, for the file at [policyPath] and the key the
/// administrator supplied, **what a product on this machine would do with
/// it** — which is the only question `inspect` exists to answer.
///
/// A product finds a policy file one of two ways, and judges it differently
/// by which:
///
/// - **at the well-known path**, where an unsigned file is honoured unless
///   the location is writable by every user;
/// - **through `CRUX_POLICY`**, where an unsigned file is always refused.
///
/// So [policyPath] is judged by the rules of the route that reaches it: the
/// well-known path's rules when it IS the well-known path, `CRUX_POLICY`'s
/// otherwise. Verifying every file as though it had arrived through the
/// variable was wrong both ways round — it refused an unsigned file that the
/// machine honours, and it could not see that a world-writable location is
/// one the machine refuses.
///
/// The key follows the same principle. When [suppliedKeyPath] is the
/// installed key file itself, it is read under the loader's own rules, so a
/// world-writable key that every product ignores is ignored here too rather
/// than verifying clean. Any other key file is the administrator's own copy
/// on their own machine, and is taken as given: a key held in a scratch
/// directory is not an installed trust root, and refusing it for sitting in
/// `/tmp` would make the diagnostic useless.
///
/// The environment is always passed explicitly, so a `CRUX_POLICY` exported
/// in the administrator's shell cannot substitute a different file for the
/// one they named.
///
/// [wellKnownPath] defaults to the platform's; tests redirect it.
PolicyLoader inspectionLoader({
  required String policyPath,
  required List<int> suppliedKey,
  String? suppliedKeyPath,
  String? wellKnownPath,
}) {
  final wellKnown = wellKnownPath ?? PolicyLoader.defaultWellKnownPath();
  final installedKey = p.join(p.dirname(wellKnown), kPolicyPublicKeyFileName);

  final atWellKnownPath = _samePath(policyPath, wellKnown);
  final keyIsInstalled =
      suppliedKeyPath != null && _samePath(suppliedKeyPath, installedKey);

  return PolicyLoader(
    trustedPublicKey: keyIsInstalled ? null : suppliedKey,
    publicKeyPath: keyIsInstalled ? suppliedKeyPath : null,
    environment: atWellKnownPath
        ? const <String, String>{}
        : <String, String>{'CRUX_POLICY': policyPath},
    wellKnownPath: wellKnown,
  );
}

/// Whether two paths name the same file, by normalized absolute path.
///
/// Lexical, not resolved: the well-known locations contain no symbolic links
/// on any platform we ship, and resolving would need a filesystem this file
/// deliberately does not touch.
bool _samePath(String a, String b) =>
    p.equals(p.canonicalize(a), p.canonicalize(b));
