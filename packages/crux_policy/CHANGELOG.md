# Changelog

## Unreleased

- **`kSuiteKeys`: the suite block has an honoured column.** New public
  `const Map<String, bool> kSuiteKeys`, beside `kProductKeys` and with the
  same meaning: `true` when some production code reads the key, `false` when
  it is registered vocabulary nothing acts on. `theme`,
  `filePathRestrictions`, `plugins` and `remoteApis` are `false`; the
  day-one keys and `audit` are `true`. Before this the suite block had nowhere
  to record that a key was dead, so an administrator who deployed
  `filePathRestrictions` got a clean lint, no startup word and no
  restriction.
- **`crux-policy lint` names an unhonoured suite key** in the same words it
  already used for an unhonoured product key (*registered but NOT honoured by
  this release … the restriction is not in force*), after any shape finding
  for the same key. A file carrying one now lints `1`. The per-key validators
  the linter uses are `kSuiteKeyValidators`, internal to the CLI; a test holds
  their key set equal to `kSuiteKeys`, and another holds every `true` key to
  having a reader.

## 0.1.0

- **The CLI is shipped as a binary.** `crux-policy` is what the Enterprise
  deployment procedure tells an administrator to run as step one, and until
  now it could not be obtained: nothing built it and nothing published it.
  `tool/build_cli.sh` is the one build — CI runs it on every push, and
  `.github/workflows/release-crux-policy.yml` runs it for a release, which
  targets macOS arm64 and x64, Linux x64 and arm64, and Windows x64,
  smoke-tests every binary (the arm64 one under emulation), Developer ID
  signs and notarizes the macOS archives, and publishes to the suite release
  bucket. The Windows binary ships unsigned until Azure signing credentials
  reach this repository. One self-contained file per platform: the bundle's
  `lib/` is empty, and the build script fails if that ever changes.
- **Usage errors exit `64` (`EX_USAGE`), not `2`.** The suite's headless
  tools now share one convention: `64` for a bad command line, small codes
  for each tool's own outcomes, `128 + N` on a signal. `2` was published in
  the policy file reference, but no binary had ever existed, so no pipeline
  can have depended on it. `4` is now described as what it always was —
  *refused*: the file would not be honoured — which includes a bad
  signature but is not limited to one.
- **`--help` and `--version` are answered anywhere on the command line**,
  on stdout with `0`, before anything is parsed or read — including after a
  subcommand, which used to be a usage error on the first thing an
  administrator ever runs. `--version` prints `crux-policy <version>`, held to
  `pubspec.yaml` by a test.
- **A mistyped command line is refused rather than reinterpreted.** Every
  token starting with `-` must be an option the subcommand actually takes,
  each subcommand has its own option table, and a stray second FILE is
  refused too. These are cases that previously exited `0` having done
  something other than what was asked:
  - `--jso` for `--json` no longer prints human output for a pipeline that
    then tries to parse it as JSON.
  - `--json` is no longer stripped before dispatch, which had made every
    subcommand appear to accept it while only `lint` and `inspect` honoured
    it.
  - `sign --key KEY FILE` signs `FILE`. The positional was "the first
    argument not starting with `-`", so the private key path was taken as the
    policy document and the policy file was never read.
  - An option missing its value, and an option value that itself begins with
    `-`, are both handled by position rather than by guessing.
- **`inspect --key` judges a file the way a product on that machine would.**
  It verified every file as though it had arrived through `CRUX_POLICY`,
  which was wrong in both directions: an unsigned file *at* the well-known
  path — which products honour — was reported refused, and a world-writable
  installed key — which products ignore — verified clean. The file is now
  judged by the route that reaches it, and the installed key under the
  loader's own rules; a key file anywhere else is the administrator's own
  copy and is taken as given. A `CRUX_POLICY` in the administrator's shell
  can no longer substitute a different file for the one named.
- **`inspect` reports what the loader found**, as `reason=… key=…
  discovery=…` — the words every product writes to its process log — and
  under `--json` a refusal is JSON on stdout (`"refused": {…}`) rather than
  a sentence on stderr.
- **`sign` accepts the private key `openssl genpkey -algorithm ed25519`
  writes** (RFC 8410 PKCS#8 PEM), alongside a 32-byte seed as base64 or hex.
  A passphrase-protected key is refused with the command that decrypts it.
- **`sign` names the Windows install location with Windows separators** on
  every host. The paths were joined with the host's rules, so a Mac printed
  `C:\ProgramData/EDACrux/crux-policy.pub`. The fix is in
  `PolicyLoader.defaultWellKnownPath` / `defaultPublicKeyPath`, which now use
  the named platform's path rules; on the host itself nothing changes. The
  public key is still the last stderr line, and a test now holds it there.
- `init`'s help no longer promises a "commented" starter file; JSON carries
  no comments.

- **The signed-policy trust model works, and is no longer inverted.** Two
  defects, one cause: nothing in any product bound `trustedPublicKey`, and
  the loader treated "no key configured" as licence to honour an unsigned
  file from `CRUX_POLICY`. So a customer who followed the documented
  procedure — sign the file, "configure the public key at install time" —
  had their file refused (`badSignature`, on a step that did not exist),
  while an unprivileged process that set `CRUX_POLICY` to an unsigned file it
  wrote had that file honoured on every machine where no administrator had
  installed a key, which is every machine. Now:
  - **The organization's public key is read from `crux-policy.pub` beside
    the well-known policy file** — `/Library/Application Support/EDACrux`,
    `%ProgramData%\EDACrux`, `/etc/edacrux` — the one directory an
    unprivileged user cannot write. `PolicyLoader()` with no arguments finds
    it there, so the default construction every product already uses *is* the
    production configuration, in the Riverpod binding and in the headless
    CLIs alike. There is deliberately no environment variable for the key: an
    env-settable trust root is what an unprivileged process can set. Tests
    redirect it with `publicKeyPath`, or implicitly by redirecting
    `wellKnownPath` (the key is looked for beside it).
  - The file accepts the base64 line `crux-policy sign` prints, 64 hex
    characters, or the PEM `PUBLIC KEY` block `openssl pkey -pubout` writes
    (RFC 8410 SubjectPublicKeyInfo); `#` comment lines are ignored.
    `PolicyPublicKey.parse` is the one parser, and `inspect --key` uses it
    too.
  - **An unsigned file via `CRUX_POLICY` is refused whatever the key state.**
    The `|| key == null` disjunct is gone; a key widens what a *signed* file
    may do and never what an unsigned one may. The trust table is documented
    on `PolicyLoader` and pinned cell by cell in `policy_loader_test.dart`.
  - A signed file with no usable key is refused with the new
    `PolicyRejection.noPublicKey` rather than `badSignature`, and the new
    `PolicyLoadResult.keyStatus` (`none` / `configured` / `malformed` /
    `unreadable` / `insecure`) says which of the four fixes applies.
  - **A world-writable well-known location is not a trusted one.** On POSIX
    the loader checks the `o+w` bit on the policy file, the key file and
    their directory; an unsigned file in a world-writable directory is
    refused with the new `PolicyRejection.insecurePath`, and a world-writable
    key file is ignored (`keyStatus: insecure`). Group-writable is allowed —
    macOS's `/Library/Application Support` is `root:admin 0775` by design.
    Windows has an ACL rather than a mode and answers false; the MSI's
    LockPermissions entry on `%ProgramData%\EDACrux` is the control there.
  - `defaultWellKnownDirectory`, `defaultPublicKeyPath`,
    `effectivePublicKeyPath` and `PolicyLoader.policyFileName` are public;
    `verify` takes an optional `key` and `insecurePath`.
- `PolicyLoader.load` no longer throws on the web. It read
  `Platform.environment` and `Platform.operatingSystem` directly, and both
  throw `UnsupportedError` in a browser — on a path every product runs before
  its first frame. `dart:io` now sits behind a conditional export; a host
  without it has no environment and no filesystem, so the loader answers
  absent, exactly as a machine with no policy file does. Environment access is
  also guarded, so a host that cannot provide one falls through to the
  well-known path. Proven in Chrome by `policy_loader_web_test.dart`.
- Initial release. `PolicyDocument` — a total parser for `.crux-policy.json`
  that ignores unknown keys.
- `PolicyLoader` — discovery (`CRUX_POLICY`, then the well-known per-platform
  path, first hit wins, never merged) and Ed25519 verification against the
  organization's own key through `crux_signing`. Missing, unreadable or
  malformed is absent; a bad signature refuses the whole file; an unsigned file
  is honoured only from the trusted well-known path once a key is configured.
- `PolicyResolver` — locked > user setting > policy default > built-in, with
  invalid values skipped, reported, and falling back to the user's setting.
- `DayOnePolicy` — the three keys that resolve before a licence exists.
- The `crux-policy` CLI (`init` / `lint` / `sign` / `inspect`) with contractual
  exit codes. Its signer lives in `tool/`, reachable only from `bin/`.
- Pure Dart with no `crux_license` dependency, both guarded on every run.
