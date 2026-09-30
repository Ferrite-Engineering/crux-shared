# Changelog

## Unreleased

- **One fingerprint per machine, not per product install.** A suite
  licence's `maxMachines` counts machines, but each product minted its own
  fingerprint in its own credential-store namespace, so four products on one
  computer looked like four machines and a three-seat suite licence was
  exhausted at the third product (found activating a suite Pro key on one
  Windows machine: the fourth product was refused). Single-product licences
  were unaffected. The fingerprint is now suite-wide: `SharedInstallFingerprint`
  keeps it in `install.fingerprint` under the shared licence directory
  (`cruxLicenseDirectory`: `~/Library/Application Support/crux/license`,
  `%LOCALAPPDATA%\crux\license`, `$XDG_DATA_HOME/crux/license`) — a plain
  file, because the OS credential store is per application on every platform
  and the fingerprint is not a secret; `%LOCALAPPDATA%` rather than
  `%APPDATA%`, because a machine identity that roams lets two computers share
  one seat. `InstallFingerprintFile` and `mintInstallFingerprint` are lifted
  from LintCrux's and SimCrux's headless CLIs, with a new `adopt` and `.shared`
  / `.legacy` factories; `InstallFingerprintSource` is the seam a product's
  store takes (required, so no test reaches the real file), with
  `InMemoryInstallFingerprintSource` for tests. All on the headless barrel.
- **An existing activation keeps its identity.** `readOrCreate(legacy: …)`
  adopts the first legacy value it finds — the product's own credential-store
  entry, then the per-product files — before minting, writes it
  write-then-rename and reads it back so racing products converge, and leaves
  the legacy entries in place for a downgrade. A product whose held machine
  id was registered under its old fingerprint gets
  `FINGERPRINT_SCOPE_MISMATCH` at its next check-in; the controller now
  releases that orphan by id before registering under the shared fingerprint,
  so the issuer side cleans itself up. When a sibling's machine already
  stands under the shared fingerprint the issuer answers `VALID` instead and
  that path never runs, so once per launch, after a `VALID` answer, the
  controller looks up the machine the fingerprint names
  (`KeygenLicenseClient.findMachine`, which now accepts only a machine
  resource carrying this fingerprint) and releases the id it held when that
  is a different machine — the case on the first computer a suite licence
  was ever used on, where every product but one was holding a seat it no
  longer needed. And a recorded issuer answer scoped to another fingerprint
  makes a check due at once rather than at the next interval, so a product
  that just adopted the shared fingerprint settles all of this on its first
  launch. An air-gapped **machine file** issued
  for an old per-product fingerprint stops validating if the shared file
  adopts a different value; support reissues it (documented, no fallback).
- **"Deactivate this machine" means the machine, suite-wide.** The release is
  made by fingerprint, which the issuer accepts in place of the machine id,
  so it works from whichever product the user is in — including one that
  never registered the machine and holds no id. The held id is the fallback
  for a refusal. A product with no id and no network now refuses to
  deactivate like any other, rather than clearing locally while a sibling's
  seat stays counted. `KeygenLicenseClient.deactivateMachine` takes `machine`
  (the id or the fingerprint); `machineId` remains as a deprecated alias
  until every product has migrated. New `findMachine` recovers the id after
  an "already activated" answer, which under a shared fingerprint is the
  normal answer when a sibling registered first.
- **A release in one product is honoured by the others.** Their next
  check-in used to find the machine unregistered and register it again,
  undoing the user's deactivation from a product they were not looking at.
  The releasing product now notes the release in `released.json` beside the
  fingerprint (`FileMachineReleaseMarker`, keyed by licence id and
  fingerprint, pruned after 180 days), and `CruxLicenseController` — which
  gains a `releaseMarker` parameter, default `NoMachineReleaseMarker` —
  consults it before any issuer contact in `start()` and `refresh()`; a
  product that finds its licence released clears its store and runs Open
  Core. `activate` clears the marker right after storing the credential and
  never consults it, so a key the user pastes after a deactivation cannot be
  cleared by it. `InMemoryMachineReleaseMarker` is for tests. The
  `readOrCreateFingerprint` doc on `LicenseStore` now says machine, not
  install; the interface is unchanged.
- New dependency on `crux_io`, for the atomic write both files go through,
  and `path` moves from dev to runtime dependencies.

- **The public beta has ended: `kBetaPeriod` defaults to `false`.** A build
  that passes no define now gates features by tier, has no beta expiry, and
  lets telemetry follow the user's consent. Nothing changes for users until a
  product release is built against this default. `--dart-define=BETA_PERIOD=true`
  restores beta behaviour in a local build. The declaration keeps its
  `bool.fromEnvironment('BETA_PERIOD', defaultValue: <bool>)` shape, because
  release pipelines read the default from source.

- **The startup policy report names unhonoured suite keys.**
  `reportPolicyLoad` now emits `policy.keysNotHonoured scope=suite keys=…`
  for every key under `suite` that `crux_policy`'s new `kSuiteKeys` marks
  `honoured: false`, before the existing per-product line. It does so whether
  or not `productId` is passed, because a suite key means the same thing to
  every product. Unrecognised keys are still not named, for the same
  forward-compatibility reason as before.

- **Removed `policyRejectionProvider` and `licenseEditionLineProvider`**,
  two public providers nothing read: no product, no overlay and no other
  package in this repository referenced either. The deprecation policy's
  removal condition — no consumer references the symbol — already held, so
  there was no migration step to deprecate for.
  `policyRejectionProvider` exposed a refused policy file "for a settings
  panel to render"; the panel that renders it is `CruxLicensePanel`, which
  reads `cruxPolicyProvider` directly because its sentence depends on the
  rejection itself. `licenseEditionLineProvider` rendered the edition line
  with the English `CruxEditionLineStringsEn` hard-wired, so no localized
  product could have used it; every product calls
  `cruxLicenseEditionLine(status, strings)` with its own strings, which is
  unchanged. The `PolicyReportDestination` doc no longer names the removed
  provider as the surface that shows a refusal.

- **`CruxUpgradeDialog.show` cannot stack.** It now holds `ModalGuard`
  (from `crux_ide_layout`, a new dependency of this package) under the new
  `CruxUpgradeDialog.modalGuardKey`, so a gated action on key auto-repeat, or
  pressed again while its denial is showing, opens one dialog rather than a
  pile of them. A suppressed call resolves at once. One product had guarded
  its own wrapper and the others had not; guarding the opener covers every
  caller. Products that open the dialog through their own `showDialog` should
  route through `show` instead.
- **The upgrade dialog has a copy contract**, documented on
  `CruxUpgradeDialogStrings`: title `Upgrade Required`, body
  `“<feature>” requires <tier>.` naming the feature every time, tier names
  qualified with the product (`WaveCrux Pro`), the platform's own `OK`, and
  `See pricing`. `CruxUpgradeDialogStringsEn` now follows it (its tier names
  stay unqualified, since it does not know the product), which changes the
  English fallback's title and sentence and the locked Settings panel's
  sentence where a product relies on the default.
- The dialog drops a trailing ellipsis from the feature name before it goes
  into the sentence: products name the feature with the label of the control
  that was activated, and "Switch Project…" is a menu label, not a noun.

- **Nothing in the credential store can extend a licence unless the issuer
  signed it.** What the issuer last said is persisted so a renewal survives a
  relaunch, and it used to be persisted as plain fields — a subscriber whose
  key had lapsed could write `{"code":"valid","expiry":"2999-…"}` into their
  own keychain and keep the tier for ever. The controller now keeps the
  issuer's response verbatim, with the Ed25519 signature Keygen puts on every
  response (over the request target, host, date and body digest), and
  re-verifies it against the account key on every load. A hand-written,
  edited, replayed-from-another-licence or copied-from-another-install entry
  fails that check and the key's own claims apply. `KeygenLicenseClient`
  refuses a validate answer that arrives without a signature that verifies,
  reporting it as not reached — a proxy that rewrites the body gets the same
  treatment as no network. Format verified against the live API with the
  account's public key. `KeygenAttestation` and
  `KeygenValidation.fromBody` / `.attested` / `.scopeFingerprint` /
  `.unreached` are new public surface; `KeygenLicenseClient` takes an
  optional `verifyKey`, defaulting to the account's.
- `KeygenValidation.machineCount` also reads the licence's
  `relationships.machines.meta.count`, which is where the issuer carries the
  seat count in use.
- **Machine files, bound to the machine they were checked out for.** A Keygen
  machine file (`-----BEGIN MACHINE FILE-----`, signed over `machine/`) is
  the third credential format: the machine is the document, the licence and
  its entitlements travel in `included`, and the machine's fingerprint is now
  a claim (`LicenseClaims.fingerprint`). `LicenseValidator.validate` takes the
  install's `fingerprint`, and a bound credential resolves only when it names
  it — `LicenseRejection.wrongMachine` otherwise, including when no
  fingerprint is supplied. This is what the offline-activation round trip
  should issue: a licence file names no machine, so one file copied to forty
  workstations activated on all forty for the whole term. Keys and licence
  files are unaffected and still import at every tier. The panel says what to
  do (`licenseErrorWrongMachine`, a concrete default on the strings base so
  existing adapters compile; override it to localise).
- **A file that finds a network is asked about like a key.** The phone-home
  used to skip licence files entirely — the file text is not a key and
  `validate-key` answered `NOT_FOUND` to it — so a file never learned about
  a cancellation, a refund or a renewal after import. The question is now
  asked about the key the file embeds (`KeygenLicenseIssuer.embeddedLicenseKey`),
  which is also what registers and releases its seat; the file itself is
  still never posted. A file that embeds no key is left to its own claims, as
  before. Air-gapped machines see no change: unreachable still keeps the tier.
- **A licence over its seat count runs Open Core on every machine until its
  owner frees one.** `TOO_MANY_MACHINES` was parsed and never acted on: a
  licence whose seat count was reduced after its machines registered kept
  every machine on the tier, so an Enterprise buyer could pay for ten seats
  once, activate ten machines, drop to one, and run ten indefinitely — seats
  are priced per machine, and the reduction is what the Stripe bridge writes
  to the licence. The controller now treats the issuer's `overage` answer as
  `CruxLicenseActivation.noSeat`, with the seat counts shown so the owner
  knows what to free in the issuer's portal; a machine already registered is
  not re-registered, and the restriction persists across relaunches like any
  other signed answer. Consequence worth knowing: lowering a policy's
  `maxMachines` floor in the catalog evicts every customer over it on their
  next check-in. Seats past the last one were already refused at activation
  under `NO_OVERAGE`; this closes the other direction.

- **A refused policy file is now said out loud, in the licence panel.** A
  policy the organization deployed and the app refused used to be a
  `policy.rejected` line on stderr and nothing else; from the keyboard a
  refused file and an absent one were the same ungoverned seat. The panel now
  opens with what happened, one sentence for *why* (the fixes differ: install
  the key, compare fingerprints, sign the file, fix the permissions), and the
  same `policy.rejected` line the process log carries, so a screenshot and a
  support bundle agree. Six new `CruxLicensePanelStrings` getters
  (`licensePolicyRefused` and one per `PolicyRejection`); every overlay's
  adapter and ARB set gains them.
- `PolicyLoadReport` payloads carry `key=<PolicyKeyStatus>` on both
  `policy.loaded` and `policy.rejected`, because `reason=noPublicKey key=none`
  and `reason=noPublicKey key=malformed` are different tickets.
- `cruxPolicyProvider`'s documentation no longer describes an
  `overrideWithValue(PolicyLoader(trustedPublicKey: …))` seam as how a host
  supplies its organization key. No product ever used it, so every signed
  policy file in the field was refused; `crux_policy` now reads the key from
  beside the well-known policy path and the default construction is the
  production configuration.
- `cruxPolicyLoader` is that default construction, named, and is what
  `cruxPolicyProvider` runs. `policy_binding_test.dart` pins it: no key bound
  in code, no redirected key or policy path, no substituted environment — the
  guard against the finding above recurring in a form that compiles.
- **A signed number too large for an int no longer throws out of the
  validator.** JSON puts no bound on a number, `1e400` decodes to
  `double.infinity`, and `Infinity.toInt()` throws `UnsupportedError` — an
  `Error`, which escapes every `on Exception`. A licence key's policy
  duration, a licence or machine file's seat count, and the counts in an
  issuer answer (`KeygenValidation.fromBody`) all read a non-finite number
  as unknown now, the same as a number of the wrong type. Reachable only
  through a payload the issuer signed, and a break of the validator's
  documented never-throws contract all the same.
- `applyPolicyLicense` has tests, end to end: a real policy file, signed and
  unsigned, the organization key installed and absent, through the real
  loader into a controller whose issuer is unreachable
  (`test/policy_license_activation_test.dart`).

## 0.13.0

- **The key field now says what it is for once a licence is active.** It used
  to keep the first-run wording — "Paste the key from your purchase email" —
  next to a licence that was already working, which reads as though the
  activation did not take.

  The field itself stays, and that is deliberate: a licence is replaced more
  often than it is first entered — EDU to Pro, Pro to Enterprise, a renewed
  key, a personal key swapped for a company one. Hiding it would strand every
  one of those. New `licenseKeyFieldHelperActive` explains replacement and
  says the current licence keeps working until a new key is entered.

- The unlicensed helper no longer says "or load a license file", which implied
  a file picker that is not wired. A licence file's *contents* paste into the
  same field, and it now says that instead.

## 0.12.0

Fixes found in the first real licensing walkthrough.

- **The Open Core panel named the wrong tiers.** It said "unlock the Pro and
  Enterprise features", which tells an educational user their key is for
  something else. Now: "unlock what it covers: Educational, Pro or Enterprise".

- **The key field crushed its own label into the pasted key.** A multi-line
  `TextField` centres `labelText` against the whole box; `alignLabelWithHint`
  plus real content padding puts it where it belongs. A 700-character base64
  key needs the legibility.

- **The offline-activation copy named no actor.** It said to "have it signed
  where there is a connection" — by whom, using what? It now leads with the
  thing that actually matters: **a key already works with no network**, because
  it is verified on the machine rather than on a server. The round trip is only
  for registering the machine so its seat counts, or for a plan this build does
  not recognise. New `licenseOfflineSteps` gives the three concrete steps.

- **`manageUrl` is now optional, and the button hides without one.**
  `supportsManageLink` is separate from `supportsPurchaseLinks` because the two
  destinations arrive at different times: a pricing page exists from day one, a
  subscription-management page needs an account page and a Stripe portal link
  that do not exist yet. A "Manage subscription" link that 404s is worse than
  no link — the user concludes their purchase is broken.

## 0.11.0

- **`CruxUpgradeDialog` offers a way to act on what it just said.** New
  optional `onSeePricing`, rendered as a filled action beside Dismiss, plus
  `CruxUpgradeDialogStrings.seePricingLabel`. Before paid licences were on sale
  there was nothing to buy, so the dialog deliberately named no purchase flow; now there is, and
  a dialog that says a feature needs Pro and then offers no way to get Pro is a
  dead end at the one moment a user is most willing to act.

  **Optional, and null by default.** `cruxSeePricingAction` returns `null` for
  `UnsupportedLicenseActions`, so an open-core build renders Dismiss alone
  rather than a button that goes nowhere. `cruxSeePricingActionFor(context)`
  resolves it from `licenseActionsProvider` through
  `ProviderScope.containerOf`, which is what lets all four products wire it in
  one line from launchers that have a `BuildContext` and no `WidgetRef` —
  every deny path is reached from a menu callback rather than a widget build.

  The dialog pops before opening the browser: coming back to a modal you
  already dealt with is the bug that guards against.

  `cruxSeePricingActionFor` is **total**: `ProviderScope.containerOf` throws
  when there is no scope above the context, and this returns `null` instead.
  The caller is a deny path — the user has already been refused something, and
  turning that refusal into a crash is strictly worse than a dialog without its
  pricing button. NetCrux's own dialog tests, which pump the widget directly,
  found this immediately.

## 0.10.0

- **The educational round trip, app side.**
  `CruxLicenseActions.requestEducationalLicense` and a panel section that
  appears only at Open Core — offering it to somebody who already holds a
  licence invites them to end up with two. The app's whole part in the flow is
  collect the address, call the endpoint, and say *check your email*: **Keygen
  sends no mail of any kind**, so the verification link, the pending-token
  store and its expiry all belong to the commerce backend, which already sends
  the suite's transactional mail.

  The address check is a courtesy, not the enforcement. Deliberately not a
  `.edu` suffix test: that is a US convention, and `ac.uk`, `edu.au` and
  `uni-*.de` are just as institutional. What it catches is the obvious
  mistake of submitting a personal address and then waiting for mail that was
  never coming.

- **Offline activation exports something real.** `exportOfflineRequest` now
  produces a `crux.offline-activation-request/v1` document carrying the
  product, the machine fingerprint a seat would be counted against, the
  machine label and the platform. It holds no secret, so it can travel on a
  USB stick or be read down a phone. The return leg is a Keygen licence file,
  which `importOfflineToken` already accepts — those embed the whole licence
  object including entitlements, which is exactly why they resolve on a
  machine that can never reach the issuer.

  The extended grace the airgap case needs was already in place: 90 days
  Enterprise, 30 Pro (`LicenseGracePolicy`, 0.9.0).

- New failure kinds `invalidEmail` and `alreadyRequested`, each with its own
  sentence in `CruxLicensePanelStrings`.

## 0.9.0

- **`CruxLicenseController` — the licensing state machine, once for all four
  products.** `LicenseService` lives in each product's Pro overlay, and it
  stays there; what moved here is the part that must
  not differ between them. Which validation code means expired, when grace
  starts, whether a failed phone-home downgrades anyone — four answers to those
  is four bugs waiting. What stays per-product is genuinely per-product: the
  credential-store binding, the machine label, the commerce URLs, and the
  provider overrides.

  Properties it exists to guarantee:

  - **A validated credential resolves with no network at all.** `start()` does
    not await the issuer; a paying customer opening the app on a plane sees
    their tier immediately.
  - **An unreachable issuer never downgrades anyone.** Every transport failure
    is reported as "offline" and changes no local state. The suite sells
    airgapped use; this is what that rests on.
  - **The issuer's expiry wins when it is later.** A renewal extends the
    licence without reissuing the key, so the key's own date is stale by
    design, and treating a renewed customer as expired is the costliest
    failure available.
  - **An unrecognised validation code changes nothing.** Keygen adds codes; a
    build that downgraded on an unknown one would downgrade customers on an
    upgrade.
  - **Deactivation refuses while offline** rather than clearing locally and
    leaving the seat counted at the issuer, which is how a customer ends up
    unable to activate their own last machine.

- **`KeygenLicenseClient`** — the three calls a licensed app ever makes:
  validate-key, activate machine, deactivate machine. **No token ships in any
  build**: the policies use `authenticationStrategy: LICENSE`, so the
  customer's own key is the credential. Injectable `http.Client`, the same
  pattern `crux_updates` and `crux_telemetry` already use.

- **`LicenseGracePolicy`** — the grace windows as data: 30 days Pro, 60 EDU, 90
  Enterprise. Grace is decided in the app, not by the billing bridge, because
  the bridge deliberately does not suspend on `past_due` while Stripe's
  dunning is still running.

- **`LicenseStore`** — the storage seam. An interface, not an implementation:
  the credential is something the user typed and must never reach
  `shared_preferences`, so each product binds it to `crux_secrets` over the OS
  credential store.

  `readOrCreateFingerprint` is deliberately *create*, not *derive*. A
  fingerprint computed from hostname or hardware changes when a user renames
  their laptop and silently burns a seat.

- All of it is on the Flutter-free `crux_license_core.dart` barrel too, so a
  headless Pro binary resolves the same licence the desktop app does.

## 0.8.1

- **The Ed25519 verifier is hand-written, and `package:cryptography` is gone.**
  0.7.0 reached for it; that was wrong, and the reason is legal rather than
  technical. The suite's export-control position rests on one load-bearing
  fact — *encryption implementations live in the closed Pro overlays; open
  core calls TLS and hashes, it does not encrypt* — and `cryptography` ships
  AES-GCM and ChaCha20. Depending on it here put a cipher in all four products
  and in the open-core tree, which at the flip means an EAR §742.15(b)
  notification obligation and makes the store builds'
  `ITSAppUsesNonExemptEncryption=false` declaration untrue. SimCrux Pro's
  `no_bundled_encryption` guard caught it.

  `lib/src/ed25519.dart` replaces it: **signature verification with no cipher in
  it** — no symmetric algorithm, no key agreement, no key generation, no
  signing. It hashes with `package:crypto`, which the position already allows.
  RFC 8032 §5.1.7, checked against the RFC's own vectors plus the malleability
  and small-order cases a naive implementation accepts
  (`test/ed25519_test.dart`).

  `crux_workspace` gained `no_bundled_encryption_test.dart`, the crux-shared
  copy of the guard the four products already had. The position asserts "nor in
  any crux-shared package" and crux-shared was the one place not testing it —
  which is exactly where a cipher does the most damage for one dependency line.

- `CruxLicenseValidator` no longer takes an `algorithm` parameter, and issuer
  selection is synchronous internally. `validate` stays `Future`-returning:
  callers do network work around it, and the signature is not worth churning.

## 0.8.0

- **`CruxLicensePanel` — Settings → License, once, for all four products.**
  The panel was first planned for each product's Pro overlay, i.e. four
  implementations of one surface, which the suite's rule of one shared
  implementation per cross-product surface forbids. The resolution: **the
  widget is shared, the service is not.** Everything product-specific arrives
  through two new provider seams, `licenseStatusProvider` and
  `licenseActionsProvider`, which each Pro overlay overrides from its own
  `LicenseService`.

  `cruxLicenseSettingsCategory()` builds the `CruxSettingsExtraCategory` with
  the stable id `pro.license` and a fixed icon, so the four overlays wire it in
  one line each and cannot drift on either.

  **The category is never tier-gated.** Not wrapped in
  `FeatureGate.isAvailable`, not hidden at `LicenseTier.openCore`, and not to
  be "made consistent" with the other `pro.*` categories by adding a tier
  check: it is how a user enters their first key, so gating it on having one is
  a deadlock. The seam is build-time, not tier-time.

- New surface: `CruxLicenseStatus` + `CruxLicenseActivation` (what the panel
  renders), `CruxLicenseActions` + `UnsupportedLicenseActions` +
  `CruxLicenseActionResult` (what it can do), `licenseStatusProvider`,
  `licenseActionsProvider`, `CruxLicensePanelStrings` +
  `CruxLicensePanelStringsEn`, `kCruxLicenseCategoryId`,
  `kCruxLicenseCategoryIcon`.

  `CruxLicenseStatus` and the actions seam are on the Flutter-free
  `crux_license_core.dart` barrel too — a headless Pro binary reports licence
  state without a widget in sight.

- New dependency on `crux_settings_ui`, for `CruxSettingsSectionCard`. The
  direction is deliberate: `crux_settings_ui` is kept to `crux_settings` +
  Flutter, and giving *it* a licence dependency would pull Ed25519 and Riverpod
  into every settings consumer in the suite.

- `LicenseGrant` gained value equality, so the status provider does not rebuild
  the panel on an equal-but-rebuilt grant.

## 0.7.0

- **The real Ed25519 licence validator.** `NoopLicenseValidator` is no longer
  the only implementation: `CruxLicenseValidator` verifies a signed credential,
  resolves what it grants, and reports every failure as a value.

  **`LicenseValidator` is a breaking change.** It was
  `LicenseTier validate(String?)`; it is now
  `Future<LicenseValidation> validate(String?, {DateTime? now})`. Async because
  Ed25519 verification is; a result type because a user pasting a bad key is
  normal input, not an exceptional condition. `LicenseValidationException` is
  removed — nothing throws for a bad credential any more. No consumer existed
  outside this package.

  New surface: `CruxProduct`, `LicenseClaims`, `LicenseGrant`,
  `LicenseValidation` (`LicenseAbsent` / `LicenseAccepted` / `LicenseExpired` /
  `LicenseRejected` + `LicenseRejection`), `LicenseIssuer`,
  `LicenseCredentialKind` / `LicenseEnvelope` / `parseLicenseCredential`,
  `KeygenLicenseIssuer`, `KeygenPolicy`, `kKeygenPolicies`,
  `kKeygenAccountId`, `kKeygenVerifyKeyHex`, `decodeHexKey`.

- **The issuer set is plural, by design.** The validator takes a *set* of
  trusted issuers, each a public key plus a mapping from its claim shape onto a
  tier and a product set. Keygen is issuer
  one; the second slot is reserved and empty, so moving EDU to self-issued
  licences later stays a configuration change.

- **Keygen does not issue a JWT, and the plan's model did not match reality.**
  A real key decodes to `key/<base64(JSON)>.<base64(signature)>` — no JWT
  header, no `alg` — carrying an account, a product, a policy and the licence,
  and **no entitlements, no tier, no email and no seat count**. What it does
  carry is the policy id, and policies are 1:1 with SKUs. So a bare key
  resolves offline through `kKeygenPolicies`, a table generated by
  the suite's SKU-catalog tooling from the same `catalog_policies()` function
  that creates the policies in Keygen, and reconciled against the live
  account at generation time.

- **Keygen licence files are accepted too**, and they win when present: the
  signed-but-unencrypted (`base64+ed25519`) form embeds the whole licence
  object including entitlements, so it resolves without the table and honours
  SKUs a build predates. That is the airgap artefact. AES-encrypted licence
  files are refused by name rather than silently mis-parsed.

- **`crux_license_core.dart` gains the whole licensing stack** and stays
  Flutter-free: the new dependency, `cryptography`, is pure Dart, so a headless
  Pro binary validates the same key the desktop app does. The barrel guard
  proves it as before.

- The validator moved from the Pro overlays' remit into this package on
  purpose. The old rationale — "a validator whose source sits beside the key
  material it checks is not a validator" — does not apply: the signing key is
  held by Keygen and never ships, and a build carries only an account id and a
  public verify key, neither of which is a secret. `crux_workspace`'s open-core purity guard was rewritten to assert
  the boundary that does matter — crux-shared may verify a signature and must
  never be able to make one.

## 0.6.0

- `package:crux_license/crux_license_core.dart` — a second, **Flutter-free**
  entry point exporting the tier vocabulary and gating arithmetic:
  `LicenseTier` (+ `LicenseTierFeatures`), `FeatureGate`, `kBetaPeriod`,
  `kAiExperimental`, the beta-expiry state machine (`kBetaExpiry`,
  `kBetaExpiryWarningDays`, `BetaExpiryStatus`, `betaExpiryStatusFor`,
  `daysUntilBetaExpiry`, `parseBetaExpiryDate`, `trustedBetaExpiryNow`) and
  the `LicenseValidator` / `NoopLicenseValidator` seam.

  The main `crux_license.dart` barrel is unchanged and stays the one a Flutter
  host imports. The new barrel exists for headless entry points: importing the
  main barrel pulls `dart:ui` into the compilation unit, which makes
  `dart build cli` / `dart compile exe` die inside the FFI transformer with
  `type 'InvalidType' is not a subtype of type 'FunctionType'`. LintCrux's Pro
  CLI had to reach into `package:crux_license/src/` behind an
  `implementation_imports` ignore to work around it; that workaround can now
  be replaced with this import.

  Everything the new barrel exports is also exported by `crux_license.dart`,
  so nothing needs both. The Riverpod provider seams and the badge/dialog
  widgets stay Flutter-only, by construction.

  `test/crux_license_core_test.dart` enforces the property two ways: it runs a
  probe program on the standalone Dart VM (which has no `dart:ui`, so the
  regression reproduces exactly as the products' CLI compile would see it) and
  it walks the barrel's transitive import closure statically.

## 0.5.0

- `CruxUpgradeDialog` — the suite-standard tier-denied dialog shown when a
  Pro/Enterprise activation is refused post-beta. Renders a title with the
  `TierBadge` chip, a body naming the feature and the tier that unlocks it,
  an optional supplemental line, and a single dismiss button. All text is
  caller-supplied via the new `CruxUpgradeDialogStrings` interface
  (`CruxUpgradeDialogStringsEn` English default), so products back it with
  their ARB files. `CruxUpgradeDialog.show` is the launcher.

## 0.4.0

Server-time hardening of the beta-expiry clock-tampering accepted risk:

- `trustedBetaExpiryNow(deviceNow, {observedServerTime})` — pure helper
  returning the later of the device clock and the most recently observed
  authoritative server time, so setting the device clock *back* can no longer
  defer beta expiry below the last server time seen. Falls back to the device
  clock when no server time has been observed (behavior unchanged).
- `observedServerTimeProvider` — Riverpod-overridable `DateTime?` (default
  `null`). The host overrides it with the `server_time` from the update
  manifest (persisted). `betaExpiryStatusProvider` and
  `betaExpiryDaysRemainingProvider` now reckon expiry against
  `trustedBetaExpiryNow(DateTime.now(), observedServerTime: …)`.

No behavior change for hosts that do not override `observedServerTimeProvider`.

## 0.2.0

Added the per-release hard build-expiry mechanism for public-beta builds
(the public beta's expiration-or-transition policy):

- `kBetaExpiry` — build-injected expiry date parsed from
  `--dart-define=BETA_EXPIRY=<yyyymmdd>`; `null` when absent/`0`/invalid
  or when `kBetaPeriod` is `false` (production builds never expire).
- `kBetaExpiryWarningDays` — warning-window constant (default 7),
  overridable via `--dart-define=BETA_EXPIRY_WARNING_DAYS=<n>`.
- `BetaExpiryStatus` enum (`notApplicable` / `active` / `expiringSoon` /
  `expired`) plus the pure `betaExpiryStatusFor(now)` and
  `daysUntilBetaExpiry(now)` functions, and the standalone
  `parseBetaExpiryDate(yyyymmdd)` helper.
- `betaExpiryStatusProvider` + `betaExpiryDaysRemainingProvider` —
  Riverpod-overridable views for the host's startup/resume check and for
  tests.

This governs build *shelf life* and is independent of `kBetaPeriod`,
which governs feature *gating*.

## 0.1.0

Promotion from the initial skeleton to the full cross-suite license
primitive surface used by every Crux product. Conversion from a pure
Dart package to a Flutter package so the Riverpod providers and the
chip widgets fit here.

Added:

- `kBetaPeriod` build-time public-beta flag (lifted from WaveCrux).
- `betaPeriodProvider` Riverpod-overridable view for tests.
- `FeatureGate` pure utility — beta short-circuit + EDU-aware Pro
  satisfaction post-beta.
- `licenseTierProvider` Riverpod `Provider<LicenseTier>` defaulting to
  `LicenseTier.openCore`. Declared as a manual provider (not
  `@Riverpod`-codegen) so consumers don't need `build_runner` for this
  primitive and the override syntax stays uniform across packages.
- `LicenseBadgeStrings` + `LicenseBadgeStringsEn` — caller-supplied
  L10N surface for the chip widgets, following the same pattern as
  `crux_theme`'s `ThemeAppearanceStrings`.
- `TierBadge` widget — PRO/ENT feature-tier chip lifted verbatim from
  WaveCrux; collapses to `SizedBox.shrink` for `openCore` / `edu`.
- `EducationalBadge` widget — EDU license-edition chip lifted verbatim
  from WaveCrux; uses `colorScheme.secondary` to remain visually
  distinct from PRO/ENT.

Conversion:

- Package upgraded to Flutter (was pure Dart) to host the providers and
  widgets. Test suite migrated to `flutter_test`.

## 0.0.1

- Initial skeleton: `LicenseTier` enum with `featureEquivalent` /
  `isEducational` extensions; `LicenseValidator` abstract interface;
  `NoopLicenseValidator` default.
