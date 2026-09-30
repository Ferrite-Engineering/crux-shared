# Changelog

## 0.1.0

- Initial release. `ed25519Verify` — Ed25519 signature verification from
  RFC 8032 §5.1.7, total over malformed input, checked against the RFC's
  vectors including the malleability and small-order cases.
- Extracted from `crux_license`'s private verifier, unchanged in algorithm and
  test vectors, so `crux_license`, `crux_policy` and plugin governance share
  one implementation.
- Verify only: no signing, no key generation, no key agreement, and no cipher
  anywhere in the dependency closure.
- Pure Dart, guarded by `no_flutter_dependency_test.dart`.
