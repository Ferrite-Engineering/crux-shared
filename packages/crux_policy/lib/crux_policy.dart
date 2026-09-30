// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Reader, verifier and precedence resolver for the signed
/// `.crux-policy.json` org-wide configuration file.
///
/// The normative contract is the policy file reference,
/// <https://edacrux.app/policy-reference>. **Where this implementation and that
/// document disagree, the document wins and this is the bug.**
///
/// This is the entire replacement for an admin console and a policy server.
/// Nothing is hosted:
/// the organization authors a file, signs it with **their own** Ed25519 key,
/// distributes it however it already distributes configuration, and points the
/// app at it.
///
/// Two properties this package exists to guarantee:
///
/// - **Total.** No input reaches a `throw`. A policy file arrives from a
///   network share and may be anything at all.
/// - **Unknown keys are ignored.** That is what lets a five-year-old client and
///   a current policy file coexist, and it is proven by a test that loads a
///   file from a hypothetical future schema version rather than assumed.
///
/// Pure Dart permanently, and with **no dependency on `crux_license`** — three
/// keys must resolve before a licence exists, so a route from here to the
/// licence machinery would let a tier lookup creep into the one path that
/// cannot have one.
library;

export 'src/day_one_policy.dart';
export 'src/policy_document.dart';
export 'src/policy_loader.dart';
export 'src/policy_resolver.dart';
export 'src/policy_value.dart';
export 'src/product_keys.dart';
