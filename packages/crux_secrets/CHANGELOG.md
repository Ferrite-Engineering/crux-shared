# Changelog

## Unreleased

- **A session with no secret service is asked once** (crux-shared#62). On
  Linux, once a call finds that libsecret cannot reach the secret service,
  `FlutterSecureStorageSecretStore` fails every later call in the process
  with the same cause, without reaching the plugin. Each call that reached it
  printed a `libsecret_error` warning, and a licence check makes several, so
  such sessions printed hundreds. A locked keyring is still asked every time.
  Tests reset the state with
  `FlutterSecureStorageSecretStore.debugForgetMissingSecretService`.

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
