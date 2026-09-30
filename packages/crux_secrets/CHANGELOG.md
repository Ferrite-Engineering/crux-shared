# Changelog

## 0.1.0

Initial release.

- `CruxSecretStore` interface — `read` / `write` / `delete` / `deleteAll`,
  with `CruxSecretStoreException` as the single failure type so callers
  never import the platform plugin to handle errors.
- `CruxSecretKey` — `(product, name)` addressing rendered as
  `crux.<product>.<name>`, validated to `[a-z0-9_]` at construction.
- `FlutterSecureStorageSecretStore` — Keychain / DPAPI / libsecret backing,
  with prefix-scoped `deleteAll` so one product cannot clear another's
  credentials.
- `InMemoryCruxSecretStore` — test and headless fake.
- `UnavailableCruxSecretStore` — the loud default binding.
- `cruxSecretStoreProvider` — the Riverpod seam hosts override.

Extracted at the moment a second consumer appeared, following the
`crux_updates` / `crux_issue_reporter` precedent: SimCrux's PR-annotation
token and the Enterprise shared-team-database password in both SimCrux and
LintCrux need the same store.
