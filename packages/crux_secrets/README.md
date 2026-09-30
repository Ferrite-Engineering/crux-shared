# crux_secrets

Cross-suite secret storage for the EDACrux suite: a narrow
read/write/delete seam over the operating system's credential store.

## Why

Every product eventually needs to persist one class of thing that must not
land in `shared_preferences`: a credential the user typed.
`shared_preferences` is a plist on macOS, a registry key on Windows and a
JSON file on Linux — all readable by anything running as the user. Fine for
a theme choice; wrong for a token that can push commit statuses to a
company's repositories, or a password that opens their database.

Consumers:

- **SimCrux** — PR-annotation auth tokens (GitHub, GitLab, webhook bearer).
- **SimCrux + LintCrux** — the Enterprise shared-team-database password.

## Wiring

```dart
ProviderScope(
  overrides: [
    cruxSecretStoreProvider.overrideWithValue(
      const FlutterSecureStorageSecretStore(),
    ),
  ],
  child: const MyApp(),
)
```

In tests, bind the in-memory fake so no test touches the developer's
keychain:

```dart
cruxSecretStoreProvider.overrideWithValue(InMemoryCruxSecretStore()),
```

## Contract

| Operation | Behavior |
|---|---|
| `read` on an absent key | returns `null` — absent is not an error |
| `write` with `null` or `''` | **deletes** the key |
| `delete` on an absent key | succeeds silently |
| any backing-store failure | throws `CruxSecretStoreException`, never a raw platform exception |

Two decisions worth knowing:

**Empty means cleared.** Writing `''` deletes rather than storing an empty
string. Otherwise a user who blanks the field and saves leaves behind a
stored empty secret that every `!= null` check downstream reads as "still
configured".

**The default binding is loud.** `cruxSecretStoreProvider` defaults to
`UnavailableCruxSecretStore`, whose writes throw. A silent in-memory
default would accept the user's token, appear to save it, and lose it on
restart — they would re-enter it forever and never be told why. `read` is
the one exception and returns `null`, because "is a credential configured?"
is a question startup code asks before the user has done anything.

## Keys

Secrets are addressed by `(product, name)`, rendered as
`crux.<product>.<name>`:

```dart
final key = CruxSecretKey(product: 'simcrux', name: 'pr_annotation_token');
```

Both halves are restricted to `[a-z0-9_]` at construction. The key reaches
platform APIs with different escaping rules (Keychain account strings,
Windows credential target names, libsecret attribute values), and a
permissive key is the kind of thing that works on the development machine
and fails on someone else's.

`deleteAll(product)` is scoped by prefix, never the plugin's global
`deleteAll()` — that would wipe every other crux product's credentials out
of the shared keychain namespace.

## Linux

`flutter_secure_storage` talks to libsecret on Linux, which needs a running
secret service (gnome-keyring, KWallet with the bridge). A headless CI
container typically has none and every call fails. That is reported
honestly through `CruxSecretStoreException` rather than papered over with a
plaintext fallback — a credential store that silently degrades to a file is
not a credential store. Hosts that must keep working there should bind
`InMemoryCruxSecretStore` and re-prompt.
