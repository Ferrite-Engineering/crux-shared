# crux_license

Cross-suite license tier vocabulary, licence validation, beta-period gating,
Riverpod tier provider, and tier-badge widgets for the EDACrux suite —
WaveCrux, NetCrux, LintCrux and SimCrux.

One package, four consumers. A customer holds one Keygen cryptographic
licence key (`key/<payload>.<signature>`, signed with Ed25519 — **not a
JWT**), a Keygen licence file, or — for a machine that will never reach the
issuer — a Keygen machine file bound to that machine's fingerprint. The credential
grants a tier and names the products it covers: one product, or all four on
a Suite SKU. Each product wires the same primitives into its open core and
its Pro overlay, so the gate behavior, the feature-tier badges and the
edition chip render identically everywhere.

## Surface

| Symbol | Purpose |
|---|---|
| `LicenseTier` + `LicenseTierFeatures` | The four-value tier vocabulary (`openCore` / `edu` / `pro` / `enterprise`) with the EDU-as-Pro-feature-equivalent mapping. |
| `kBetaPeriod`, `betaPeriodProvider` | Build-time public-beta flag and its Riverpod-overridable view for tests. |
| `kBetaExpiry`, `kBetaExpiryWarningDays`, `BetaExpiryStatus`, `betaExpiryStatusFor`, `daysUntilBetaExpiry` | Per-release hard build-expiry mechanism. Expiry date injected via `--dart-define=BETA_EXPIRY=<yyyymmdd>` (absent/`0` ⇒ never expires); only active while `kBetaPeriod` is on. |
| `betaExpiryStatusProvider`, `betaExpiryDaysRemainingProvider` | Riverpod-overridable views of the expiry status and days remaining for the host's startup/resume check. |
| `FeatureGate.isAvailable` | Pure utility — short-circuits to `true` while `kBetaPeriod` is on; otherwise compares the active tier (via `featureEquivalent`) against the gate's required tier. |
| `licenseTierProvider` | Riverpod provider exposing the active tier. Defaults to `LicenseTier.openCore`; each product's Pro overlay overrides it from the `CruxLicenseController` it constructs. |
| `kAiExperimental`, `aiExperimentalBuildFlagProvider`, `aiExperimentalUserToggleProvider`, `aiExperimentalEnabledProvider` | The two-part gate on the Experimental AI Assistant. See "Experimental AI gating" below. |
| `LicenseValidator` + `CruxLicenseValidator` + `NoopLicenseValidator` | The Ed25519 licence validator and its seam. `CruxLicenseValidator` lives here, in the open: it verifies a credential against a set of trusted issuers and resolves it to a `LicenseGrant`. `CruxLicenseValidator.production(product: …)` is the shipping configuration. `NoopLicenseValidator` grants nothing — Open Core is the absence of a licence. |
| `CruxProduct`, `LicenseClaims`, `LicenseGrant`, `LicenseValidation` | The vocabulary of a validation. Validation is total: every malformed, tampered, expired or wrong-product credential is an outcome to render, never an exception to catch. |
| `KeygenLicenseIssuer` + `kKeygenPolicies` | Issuer one, and the generated policy table that resolves a bare licence key — which carries a policy id and no entitlements — to a tier and product set with no network. A licence file embeds its entitlements and resolves without the table; a machine file does the same and resolves only on the install whose fingerprint it names. |
| `KeygenLicenseClient`, `CruxLicenseController`, `LicenseGracePolicy` | The rest of the lifecycle: activation, periodic validation, and how long each tier keeps working after the issuer stops confirming it. |
| `SharedInstallFingerprint`, `InstallFingerprintFile`, `InstallFingerprintSource`, `mintInstallFingerprint`, `cruxLicenseDirectory` | The machine's one fingerprint, shared by every product on it through a plain file so a suite licence's seats count machines rather than installs. See "Machine fingerprint" below. |
| `MachineReleaseMarker` + `FileMachineReleaseMarker` / `NoMachineReleaseMarker` / `InMemoryMachineReleaseMarker` | The note one product leaves for the others when it releases the machine's seat, so their next check-in does not silently register it again. |
| `CruxLicensePanel` + `CruxLicensePanelStrings` | The License Settings category. |
| `cruxPolicyProvider`, `dayOnePolicyProvider`, `cruxPolicyOverrides`, `applyPolicyLicense` | The `.crux-policy.json` binding: a licence the organization deploys goes through the same `activate` path a pasted key does. |
| `LicenseBadgeStrings` + `LicenseBadgeStringsEn` | Caller-supplied localization surface for the chip widgets. |
| `FeatureTierBadge` | PRO/ENT feature-tier chip rendered next to a feature label — "this feature requires PRO". Takes the tier as an argument; renders nothing for `openCore` / `edu`. |
| `EditionBadge` | Edition chip — "you are running PRO". Reads `licenseTierProvider` and renders PRO, ENT or EDU; renders nothing at `openCore`, so it can be mounted unconditionally. |
| `CruxUpgradeDialog` + `CruxUpgradeDialogStrings` / `CruxUpgradeDialogStringsEn` | The suite-standard tier-denied dialog: title with `FeatureTierBadge`, body naming the feature and required tier, optional supplemental line, single dismiss button. Shown via `CruxUpgradeDialog.show` when a gated activation is refused post-beta. |

## Two entry points

```dart
import 'package:crux_license/crux_license.dart';       // Flutter hosts
import 'package:crux_license/crux_license_core.dart';  // headless hosts
```

The main barrel is what a Flutter app imports and covers the whole surface
table above. `crux_license_core.dart` is a **Flutter-free** subset of it —
`LicenseTier`, `LicenseTierFeatures`, `FeatureGate`, `kBetaPeriod`,
`kAiExperimental`, the beta-expiry state machine, and the whole licensing
stack from `CruxLicenseValidator` to the generated policy table — with no
Flutter, no Riverpod and no `dart:ui` anywhere in its transitive import
closure. A headless Pro binary validates the very same key the desktop app
does.

It exists because importing the main barrel pulls `dart:ui` into the
compilation unit, and a headless entry point compiled with `dart build cli` /
`dart compile exe` then dies inside the FFI transformer with `type
'InvalidType' is not a subtype of type 'FunctionType'` — no source location,
no named library. Every product in the suite ships (or will ship) a CLI that
gates Pro subcommands, so the seam lives here rather than in each product's
workaround.

The provider seams (`licenseTierProvider`, `betaPeriodProvider`,
`betaExpiryStatusProvider`, `aiExperimentalEnabledProvider`, …) and the badge
and dialog widgets are Flutter-only and stay on the main barrel. A headless
host has no `ProviderContainer`; it passes the active tier to
`FeatureGate.isAvailable` directly.

`test/crux_license_core_test.dart` is the guard: it runs a probe program on
the standalone Dart VM, which has no `dart:ui`, so a re-acquired Flutter
dependency fails here rather than at a product's release build.

## Wiring it in (per product)

```dart
// 1. Adapter that bridges the product's AppLocalizations to the package
// strings interface.
class WaveCruxLicenseBadgeStrings extends LicenseBadgeStrings {
  WaveCruxLicenseBadgeStrings(this._l10n);
  final L10N _l10n;

  @override String get tierBadgePro => _l10n.tierBadgePro;
  @override String get tierBadgeProSemantic => _l10n.tierBadgeProSemantic;
  @override String get tierBadgeEnterprise => _l10n.tierBadgeEnterprise;
  @override String get tierBadgeEnterpriseSemantic =>
      _l10n.tierBadgeEnterpriseSemantic;
  @override String get tierBadgeEdu => _l10n.tierBadgeEdu;
  @override String get tierBadgeEduSemantic => _l10n.tierBadgeEduSemantic;
  @override String get editionBadgeProSemantic =>
      _l10n.editionBadgeProSemantic;
  @override String get editionBadgeEnterpriseSemantic =>
      _l10n.editionBadgeEnterpriseSemantic;
  @override String get editionBadgeEduSemantic =>
      _l10n.editionBadgeEduSemantic;
}

// 2. In the Pro overlay's overrides, replace the open-core defaults with the
// overlay's own licence service and store.
final proOverrides = <Override>[
  licenseStatusProvider.overrideWith(...),
  licenseActionsProvider.overrideWith(...),
  licenseTierProvider.overrideWith(...),
  // ...other Pro overrides
];

// 3. Wrap a feature label with FeatureTierBadge wherever a Pro/Enterprise
// feature surfaces in the open-core UI. The widget collapses to
// SizedBox.shrink for openCore/edu, so unconditional wrapping is safe.
Row(children: [
  Text(label),
  const SizedBox(width: 8),
  FeatureTierBadge(
    requiredTier: feature.requiredTier,
    strings: WaveCruxLicenseBadgeStrings(L10N.of(context)),
  ),
]);
```

## Beta-period semantics

The public beta has ended: `kBetaPeriod` defaults to `false`, so
`FeatureGate.isAvailable` compares the active tier against the gate's
required tier, and a build without a define ships that behaviour.

While `kBetaPeriod` is `true` — a local build made with
`--dart-define=BETA_PERIOD=true` — `FeatureGate.isAvailable` short-circuits
to `true` for every call. Tier badges still render, because they are
communication, not enforcement. Tests that need the beta path override
`betaPeriodProvider` to `true` rather than relying on the default.

The default lives in `packages/crux_license/lib/src/beta_period.dart`, and
each product's release pipeline reads it from there, so keep the
`bool.fromEnvironment('BETA_PERIOD', defaultValue: <bool>)` shape. Every
product picks up a change to it the next time it moves its `crux-shared`
submodule pin.

## Beta build-expiry semantics

Separate from feature gating: `kBetaPeriod` controls whether features are
*gated*; the build-expiry mechanism controls each beta build's *shelf
life* so stale betas stop running and users move onto the current drop.

Each beta release is built with `--dart-define=BETA_EXPIRY=<yyyymmdd>`
(e.g. `20260901`). Absent or `0` means the build never expires — every
developer build and every post-beta production build (`kBetaPeriod` is
`false`) is unaffected. The warning window defaults to 7 days and is
overridable with `--dart-define=BETA_EXPIRY_WARNING_DAYS=<n>`.

`betaExpiryStatusFor(DateTime.now())` returns one of:

- `notApplicable` — no expiry injected, or a production build. Host shows
  nothing.
- `active` — expiry set, more than the warning window away. Host shows
  nothing.
- `expiringSoon` — within the warning window. Host shows a dismissible
  "expires soon" banner with `daysUntilBetaExpiry` remaining.
- `expired` — expiry date reached or passed. Host shows a blocking,
  non-dismissable "download the latest build" modal.

The host reads the status at startup and on app resume (never
mid-session) via `betaExpiryStatusProvider`, invalidating it on resume to
re-evaluate against the latest clock reading. The check trusts the device
clock, but not the device clock alone: `trustedBetaExpiryNow` takes the
later of the device clock and the most recent authoritative server time
the app has observed. The host supplies that watermark by overriding
`observedServerTimeProvider` with the `server_time` its update-manifest
check returns, persisted so a later offline launch still benefits.
Winding the clock back therefore cannot defer expiry below the last
server time seen. Moving it forward, or never coming online at all,
still falls back to the device clock — accepted, because the mechanism
exists to retire stale builds, not to resist a determined attacker.

## Experimental AI gating

The Experimental AI Assistant is gated **twice**, and both gates must be
open before any AI surface appears:

| Gate | Symbol | Default | Who sets it |
|---|---|---|---|
| Build flag — does AI exist in this binary? | `kAiExperimental` / `aiExperimentalBuildFlagProvider` | `true` | The build: `--dart-define=AI_EXPERIMENTAL=false` omits the feature entirely. |
| User opt-in — has this user turned it on? | `aiExperimentalUserToggleProvider` | `false` | The host, overriding it with its own persisted setting. |

`aiExperimentalEnabledProvider` is the AND of the two, and it is the only
one feature code should read. The build flag governs the *existence* of
the surface (including the Settings → AI section that hosts the toggle);
the user toggle governs whether anything is actually active.

The default is `true` because the feature has graduated out of
"hidden behind a build flag" — a normal build now carries the AI surface,
still *labeled* Experimental, still inert until the user opts in and
supplies their own key. The build flag is retained as an exit ramp: AI
behavior is the least predictable surface in the suite and depends on
third-party endpoints nobody here controls, so a build can omit it
entirely, and the feature can be withdrawn before the open-core flip
without breaking a shipped promise — because it was never presented as
stable.

The flag lives here, in `crux_license`, rather than in each product,
so changing the suite-wide posture is one line instead of a sweep across
four repos. It sits alongside `kBetaPeriod` (feature gating) and
`kBetaExpiry` (build shelf life) — the suite's three shared build-time
switches, all single-sourced in this package.

## EDU semantics

The `edu` tier is **feature-equivalent to `pro`** — the EDU distinction
is in licensing terms (non-commercial use, annual `.edu`-email
verification, 60-day grace on renewal), not feature access.
`FeatureGate.isAvailable` uses `LicenseTierFeatures.featureEquivalent`
on the current tier, so EDU satisfies any Pro-tier gate. No feature
should ever be gated specifically on `LicenseTier.edu`; use
`LicenseTier.pro` as the gate's required tier instead.

`FeatureTierBadge` therefore renders nothing for EDU (an "EDU-required"
feature label is meaningless). The edition the user is running is surfaced
separately by `EditionBadge` on user-status surfaces (About box, status bar,
Welcome screen), and EDU keeps its own colour there, so the user (and anyone
reviewing the screen) knows the app is running under non-commercial terms.

## Why the validator is in the open

The Ed25519 signature check is here, not in a closed overlay, because there
is no private key material to sit next to. Keygen generates and holds the
signing key; it is in no repository and no CI secret store. What a build
carries is a Keygen account id and a public verify key, neither of which is a
secret, so publishing the verification routine reveals nothing that verifying
a signature did not already reveal.

The rest of the lifecycle is in the open for the same reason. Activation
against Keygen, machine identity, the grace windows and the periodic
re-validation cadence are `KeygenLicenseClient`, `LicenseMachineIdentity`,
`LicenseGracePolicy` and `CruxLicenseController`, here, written once because
those are the decisions that must not differ between products.

What each Pro overlay supplies is narrow: its own `LicenseStore` (the
credential-store namespace) and a thin per-product service that constructs
`CruxLicenseController` with the product's identity, store and commerce URLs,
wired in by overriding `licenseStatusProvider`, `licenseActionsProvider` and
`licenseTierProvider`. Open-core builds keep the defaults —
`CruxLicenseStatus.openCore` and `UnsupportedLicenseActions` — and run at
Open Core tier.

## Machine fingerprint

The issuer counts a licence's seats by machine fingerprint, and a suite
licence's `maxMachines` counts **machines**. So every product on a computer
must present the same fingerprint, or four products look like four machines
and a three-seat suite licence is exhausted at the third product. The
fingerprint is therefore suite-wide, and a product's `LicenseStore` answers
`readOrCreateFingerprint` from `SharedInstallFingerprint` rather than from a
secret of its own.

**What it is.** Sixteen random bytes, base64url, unpadded
(`mintInstallFingerprint`). Minted, not derived: a fingerprint computed from
hardware or hostname changes when a user renames their laptop and silently
burns a seat. It is URL-safe by construction, which lets it stand in for the
machine's id on the issuer's machine endpoints.

**Where it lives.** `install.fingerprint` under the suite's shared licence
directory (`cruxLicenseDirectory`):

| Platform | Directory |
|---|---|
| macOS | `$HOME/Library/Application Support/crux/license` |
| Windows | `%LOCALAPPDATA%\crux\license` |
| Linux / other | `${XDG_DATA_HOME:-$HOME/.local/share}/crux/license` |

**Why a file, not the credential store.** The OS credential store is per
application on every platform — a macOS keychain item is ACL'd to the app
that created it and a cross-app read prompts; Windows keeps the suite's
secrets in a per-application DPAPI store; libsecret keys its schema by
application id — so it cannot hold a value four products share. The
fingerprint is not a secret (the issuer holds it, the offline activation
request carries it in plain text, a machine file names it in its signed
payload), so a plain file loses nothing. The credential store keeps what is
genuinely per product: the key, the machine id, the issuer's last answer.

**Why `%LOCALAPPDATA%`.** Roaming AppData follows a user to other computers
under a roaming profile. A machine identity that roams lets two computers
present one fingerprint, hold one seat between them and share one machine
record at the issuer. Local AppData stays on the machine.

**Migration.** `SharedInstallFingerprint.readOrCreate(legacy: …)` resolves,
first hit wins: the shared file; then the legacy sources the product lists
(its own credential-store entry, then the per-product files earlier releases
wrote — `InstallFingerprintFile.legacy('lintcrux')`, `…('simcrux')`, still
read from `%APPDATA%` on Windows); then mint. The value chosen is written
write-then-rename and **read back**, so two products racing on one machine
converge on the value that stuck. Legacy entries are left in place so a
downgrade still finds its fingerprint. A product whose stored machine id was
registered under an old per-product fingerprint gets
`FINGERPRINT_SCOPE_MISMATCH` at its next check-in; the controller releases
that orphan machine by id before registering under the shared fingerprint,
so no manual cleanup at the issuer is needed. An air-gapped install holding
a **machine file** issued for an old per-product fingerprint stops validating
if the shared file adopts a different value; support reissues the machine
file for the shared fingerprint.

**Release marker.** "Deactivate this machine" now releases the machine at
the issuer by fingerprint, so it works from whichever product the user is in.
The other products still hold the key, and their next check-in would find
the machine unregistered and register it again. So the releasing product
notes the release in `released.json` beside the fingerprint
(`FileMachineReleaseMarker`, keyed by licence id **and** fingerprint, entries
pruned after 180 days), and every controller consults the marker before it
contacts the issuer — a product that finds its licence released drops the
key and runs Open Core. Activating a licence clears its marker, so a key the
user pastes after a deactivation is never cleared by it. The controller's
default is `NoMachineReleaseMarker`; each product's service passes
`FileMachineReleaseMarker()`.

A test never touches the real shared directory: `SharedInstallFingerprint`
and `FileMachineReleaseMarker` take an `environment` map and an
`operatingSystem`, and `InMemoryInstallFingerprintSource` /
`InMemoryMachineReleaseMarker` need no disk at all. Every product's store
takes its `InstallFingerprintSource` as a required constructor parameter for
the same reason.

## Visibility & license

Licensed under Apache 2.0, like the rest of `crux-shared`. Private during
the public beta; public at the post-beta open-core flip, alongside every
product's open-core repo. The package is consumed by each product's open core
via a Git submodule at `<product>/crux-shared/` plus a `path:` dep in
`pubspec.yaml`; the Pro overlays inherit it transitively through the
open-core submodule.
