# crux_policy

Reader, verifier and precedence resolver for `.crux-policy.json` — the signed,
org-wide configuration file every EDACrux product honours — plus the
`crux-policy` CLI that authors, lints, signs and inspects it.

**The normative contract is the policy file reference,
<https://edacrux.app/policy-reference>. Where this package and that document
disagree, the document wins and this is the bug.**

## What this replaces

An admin console and a policy server. **There is no console and there will not
be one.** Nothing
is hosted: the organization authors a file, signs it with **their own** Ed25519
key, distributes it however it already distributes configuration (a network
share, a git checkout, an MDM profile, a config-management run), and points the
app at it.

## Getting the binary

`crux-policy` is a single self-contained executable. Each archive holds that
one file plus `LICENSE` and `NOTICES`; there is nothing to install and nothing
beside it to keep.

```
https://updates.edacrux.app/<version>/crux-policy-<version>-<platform>.<ext>
```

| Platform | Archive |
|---|---|
| macOS, Apple silicon | `crux-policy-<version>-macos-arm64.zip` |
| macOS, Intel | `crux-policy-<version>-macos-x64.zip` |
| Linux x86-64 | `crux-policy-<version>-linux-x64.tar.gz` |
| Linux arm64 | `crux-policy-<version>-linux-arm64.tar.gz` |
| Windows x86-64 | `crux-policy-<version>-windows-x64.zip` |

`crux-policy-<version>-SHA256SUMS` sits beside them. **There is deliberately
no `latest` alias**: a CI runner that silently changed the version of the tool
checking its policy file would be a worse problem than an out-of-date pin.

The macOS archives are Developer ID signed and notarized, so unzip-and-run
works; Gatekeeper resolves the ticket online on first run, because a ticket
cannot be stapled to a bare executable. **The Windows binary is not yet
Authenticode signed** — the signing credentials live with the product
repositories, not this one — so SmartScreen warns on first run; verify it
against the checksum list. The Linux binaries need **glibc 2.28 or later**
(RHEL 8, Debian 10, Ubuntu 20.04 and newer); the release measures the real
requirement and refuses to publish one that exceeds that.

`.github/workflows/release-crux-policy.yml` is the pipeline. To build one
yourself from a checkout of this repository, with the `dart` that ships with
the Flutter SDK:

```bash
flutter pub get
packages/crux_policy/tool/build_cli.sh     # -> packages/crux_policy/build/cli/crux-policy
```

## The CLI

```
crux-policy init [--out FILE]
crux-policy lint FILE [--json]
crux-policy sign FILE --key PRIVATE_KEY_FILE [--out FILE]
crux-policy inspect FILE --product PRODUCT [--key PUBLIC_KEY_FILE] [--json]
```

`--help` (or `-h`) and `--version` are answered wherever they appear — on the
bare command or after a subcommand — on stdout, with exit 0, before anything
is read.

Exit codes are a contract — a CI step branches on them:

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | lint findings |
| 3 | I/O error |
| 4 | refused — the file would not be honoured (a bad signature, no usable key, or an unsigned file somewhere a product would not trust it) |
| 64 | usage error (`EX_USAGE`) |
| 130 / 143 | interrupted / terminated (`128 + signal`) — a cancelled CI job, never a result |

64 rather than a small number because it must never be mistaken for an
outcome: a step that branches on "findings" cannot confuse a typo in its own
command line with one. It is the convention every headless tool in the suite
follows.

**A mistyped command line is refused, not reinterpreted.** Every token
starting with `-` must be an option that subcommand actually takes, each
subcommand has its own option table, and a stray second FILE is an error too —
all of them exit 64. Ignoring any of it would be worse than any exit code,
because the run then *succeeds* having done something other than what was
written: `--jso` for `--json` prints human output that a pipeline parses as
JSON and fails on somewhere else entirely.

**`lint` reports every problem at once.** An administrator fixing a policy file
one error per run is an administrator who stops using the tool.

**`inspect` is the "why is my setting greyed out" answer.** Without `--key` it
reports what the file resolves to and says on its own output that it did not
check the signature — it is a local diagnostic run by the person holding the
file, and refusing to look would make it useless in exactly the situation it
exists for.

With `--key` it answers **what a product on this machine would do with the
file where it is**, by the loader's own rules: a file at the well-known path is
judged as one found there (an unsigned file is honoured unless the location is
writable by every user), a file anywhere else as one reached through
`CRUX_POLICY` (an unsigned file is refused). If `--key` names the installed
`crux-policy.pub` itself, it is read as the loader reads it, so a
world-writable key is ignored here exactly as it is by the products; any other
key file is your own copy and is taken as given. The outcome is printed as
`reason=… key=… discovery=…`, the words every product writes to its process
log, and under `--json` a refusal is JSON on stdout.

**`sign` takes the private key as a 32-byte seed (base64 or hex) or as the
PEM `openssl genpkey -algorithm ed25519` writes**, and prints the corresponding
public key to stderr, because it is needed on every machine and deriving it by
hand is an error nobody should have to make. **The key is always the last
stderr line**, so `2>&1 >/dev/null | tail -1` captures it. It goes in
`crux-policy.pub` beside the well-known policy file — see "Where the key lives"
below.

### Keeping the file in git is the recommended deployment

It gives a team a better change history for rule policy than a console would,
reviewed with tooling they already run. That is why this is a CLI with
meaningful exit codes and machine-readable output rather than a web app.

## Where the signer lives

`crux_signing` **verifies and cannot sign**, deliberately: no product build may
contain signing code, because that is what keeps open core free of non-exempt
encryption for export control, and every store listing's
`ITSAppUsesNonExemptEncryption=false` true.

The `sign` subcommand needs a real signer, so it lives in
[`tool/policy_signer.dart`](tool/policy_signer.dart), reachable only from
`bin/`. It is **not exported from the package barrel**, and every product
imports exactly that barrel — so nothing a product can name can reach it. The
proof is mechanical rather than a promise: the export-control guard resolves
each product's real dependency closure.

A separate signing package taken as a `dev_dependency` was the other candidate
and is worse — it would put a signer in the resolved dev closure of every
consumer, and "dev dependencies do not ship" is a claim about a build system
rather than a fact about the source tree.

## Two properties this package guarantees

- **Total.** No input reaches a `throw`. A policy file arrives from a network
  share and may be anything at all. That includes the host: in a browser there
  is no environment and no filesystem, so `PolicyLoader.load` answers absent
  there instead of letting `dart:io` throw into app startup — `dart:io` sits
  behind a conditional export, and CI runs the package's tests in Chrome.
- **Unknown keys are ignored.** That is what lets a five-year-old client and a
  current policy file coexist. Proven by a test that loads a file from a
  hypothetical future schema version, not assumed.

## Two failures that look alike and must not be confused

| Situation | Behaviour | Why |
|---|---|---|
| missing / unreadable / malformed | → absent | failing closed **bricks a deployment** over a typo |
| present, signature does not verify | → **refuse the whole file** | failing open is **self-granting**, which is the entire reason it is signed |

An unsigned file is honoured **only from a trusted path** — the well-known
per-platform location, which needs administrator rights to write.

## Where the key lives

The organization's Ed25519 public key is read from **`crux-policy.pub` in the
same directory as the well-known policy file**, and from nowhere else:

| Platform | Key file |
|---|---|
| macOS | `/Library/Application Support/EDACrux/crux-policy.pub` |
| Windows | `%ProgramData%\EDACrux\crux-policy.pub` |
| Linux | `/etc/edacrux/crux-policy.pub` |

That placement is the design. The policy file may travel — a network share,
`CRUX_POLICY` in a pipeline — because the key that vouches for it does not: it
is installed once, by an administrator, into the one directory an unprivileged
user cannot write. **There is deliberately no environment variable for the
key.** An env-settable trust root is exactly what an unprivileged process can
set; it would sign its own policy and point the app at both. The only override
is the `PolicyLoader` constructor (`trustedPublicKey`, `publicKeyPath`), which
a process cannot reach — that is `inspect --key`'s seam and a test's.

The file holds the base64 line `sign` prints, 64 hex characters, or the PEM
`PUBLIC KEY` block `openssl pkey -pubout` writes. `#` comment lines are
ignored.

`PolicyLoader()` with no arguments finds it, so the default construction every
product uses — in the Riverpod binding and in the headless CLIs — is the
production configuration. Nothing is compiled in.

### The trust table

| file | found via | key installed | outcome |
|---|---|---|---|
| signed, verifies | anywhere | yes | **honoured** |
| signed, does not verify | anywhere | yes | refused — `badSignature` |
| signed | anywhere | no | refused — `noPublicKey` |
| unsigned | well-known path | either | **honoured** |
| unsigned | `CRUX_POLICY` | either | refused — `untrustedUnsigned` |

A key widens what a **signed** file may do; it never widens what an unsigned
one may. On POSIX a well-known location that is writable by every user is not
trusted: an unsigned file there is refused (`insecurePath`) and a
world-writable key file is ignored (`keyStatus: insecure`). Group-writable is
fine — macOS's `/Library/Application Support` is `root:admin 0775` by design.
`PolicyLoadResult.keyStatus` says what the loader found when it looked for the
key, so "no key" is never one ticket for four causes.

## Not in this package

- **No Flutter, ever.** The `lintcrux` CLI reads this file for its gate
  threshold and is a bare Dart process. Guarded on every run.
- **No dependency on `crux_license`.** Three keys must resolve *before* a
  licence exists (<https://edacrux.app/policy-reference#three>), so a route to the licence machinery is how a tier
  lookup creeps into the one path that cannot have one. Also guarded.
- **No Settings UI.** "Show this value as locked, and name its source" lands per
  product; if it ever wants sharing it becomes `crux_policy_ui`, following
  `crux_settings` / `crux_settings_ui`.
