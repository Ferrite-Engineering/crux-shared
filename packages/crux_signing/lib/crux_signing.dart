// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Ed25519 signature **verification** for the EDACrux suite, and nothing else.
///
/// One verifier, three consumers: `crux_license` resolves licence keys and
/// licence files, `crux_policy` verifies the organization's signed
/// `.crux-policy.json`, and plugin governance checks a decoder's signature.
/// There is exactly one Ed25519 implementation in the suite and this is it.
///
/// ### What is deliberately absent
///
/// **No signing, no key generation, no key agreement, no cipher.** The public
/// surface is a single verify entry point. Signing a policy file is the
/// organization's job, done with their own key by the `crux-policy` CLI's
/// signer — which is a dev-time dependency of that tool and **ships in no
/// product build**, because a product that contains signing code is no longer
/// free of non-exempt encryption for export control, and every store listing's
/// `ITSAppUsesNonExemptEncryption=false` becomes untrue.
///
/// Verification is not encryption. That distinction is the whole reason this
/// package can exist in `crux-shared` at all.
library;

export 'src/ed25519.dart';
