# crux_signing

Ed25519 signature **verification** for the EDACrux suite, and nothing else.
Pure Dart, permanently.

```dart
import 'package:crux_signing/crux_signing.dart';

final ok = ed25519Verify(
  message: utf8.encode(payload),
  signature: signatureBytes, // 64 bytes
  publicKey: publicKeyBytes, // 32 bytes
);
```

That one function is the whole public surface.

## One verifier, three consumers

- **`crux_license`** — Keygen licence keys and licence files.
- **`crux_policy`** — the organization's signed `.crux-policy.json`, which
  arrives from a network share an attacker may be able to write to.
- **Plugin governance** — a decoder or widget allowlisted by signing key.

There is exactly one Ed25519 implementation in the suite and this is it. It
began as `crux_license`'s private verifier and moved here when the second and
third callers appeared, because a second implementation is the failure this
package exists to prevent.

## Why it is hand-written

`package:cryptography` is the obvious dependency and cannot be used. It ships
AES-GCM and ChaCha20, so taking it would put a cipher in every product and in
the open-core tree — which changes the suite's export-control position and
makes every store build's `ITSAppUsesNonExemptEncryption=false` declaration
untrue. Verification is not encryption, and that distinction is the reason
this package can exist in `crux-shared` at all.

So the dependency set is `package:crypto` (SHA-512, which Ed25519 is defined
over, and no cipher) and `package:meta`. `no_bundled_encryption_test.dart` in
`crux_workspace` fails if a known encryption package resolves anywhere in the
workspace, transitively included.

## What is deliberately absent

**No signing, no key generation, no key agreement.** Signing a policy file is
the organization's job, done with its own key by the `crux-policy` CLI, whose
signer is reachable only from that CLI and ships in no product build. Tests
sign with a fixture signer under `test/support/`.

## Correctness

Implemented from RFC 8032 §5.1.7 and checked against the RFC's own test
vectors, including the malleability and small-order cases a naive
implementation accepts. Rejecting bad input is the entire job, so the negative
vectors matter more than the positive ones.

- **Total.** Every malformed input — a wrong length, a public key that is not
  a curve point, a non-canonical scalar — returns `false` rather than throwing.
- **Not constant-time, deliberately.** Every input is public by design; there
  is no secret to leak through a timing channel.

## Not in this package

- **No Flutter, ever.** Headless `dart build cli` binaries verify licences and
  policy files through it. `no_flutter_dependency_test.dart` walks the resolved
  dependency closure on every run.
