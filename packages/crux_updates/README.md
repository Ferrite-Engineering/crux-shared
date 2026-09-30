# crux_updates

Cross-suite update-check mechanism for the EDACrux suite — WaveCrux,
NetCrux, LintCrux and SimCrux.

One implementation of "is there a newer release, and how do I tell the
user?": the version-manifest model with fail-soft parsing and semver
comparison, the HTTP fetch service and its no-op counterpart, the
Riverpod notifier that drives launch / periodic / manual checks, and the
dismissible update banner. Everything product-specific — the manifest
URL, the product name, the download and store targets, the localized
copy, the "auto-check" setting, the URL launcher — arrives through
configuration or an overridable provider, so the package itself knows
nothing about any one product.

Extracted from the shipped WaveCrux implementation. WaveCrux has not
migrated onto it yet; NetCrux, SimCrux and LintCrux are the first
consumers.

## Surface

| Symbol | Purpose |
|---|---|
| `CruxUpdateConfig` (+ `.fromUris`) | The one piece of per-product configuration: manifest URI, product display name, download page, optional App Store / Play Store URIs, `checkOnMobile`, fetch timeout, auto-check interval. `updateTargetFor(platform)` resolves the "Update Now" destination. |
| `CruxUpdateStrings` / `CruxUpdateStringsEn` | Caller-supplied localization surface. One getter per user-visible string; version interpolation is a method (`bannerMessage(version)`, `checkUpToDate(version)`), never a format template. The English default is for tests, prototypes and un-localized builds. |
| `UpdateInfo`, `UpdateManifest` | The manifest model. `UpdateManifest.tryParse` and `UpdateInfo.fromJson` **fail soft** — malformed JSON, a missing `latest`, or a missing `version` yields `null`, never a throw. `isNewerThan` / `meetsMinSupported` do the semver comparison. |
| `UpdateEdition` (`unlocked` / `openCore`) | Whether this seat has paid features unlocked, and `offers(info, currentVersion:)` — the rule for which releases matter to it. See [Releases that change only paid features](#releases-that-change-only-paid-features). |
| `UpdateStatus` (`…Current` / `…Checking` / `…Available` / `…Error`) | Sealed four-state outcome held by `updateStatusProvider`. |
| `UpdateCheckService`, `UpdateCheckException` | The service seam. `checkForUpdate()` returns `null` when current, an `UpdateInfo` when an update exists, and throws exactly one typed `UpdateCheckException` on any failure. |
| `HttpUpdateCheckService`, `NoopUpdateCheckService` | The live manifest fetcher and the always-current stand-in. |
| `updateStatusProvider` + `UpdateStatusNotifier` | Keep-alive notifier. Fires a launch check, runs a periodic timer, exposes `runScheduledCheck()` (gated) and `checkNow()` (never gated). |
| `updateCheckServiceProvider` | Picks the live service or the no-op (mobile store build / build info not yet loaded). |
| `UpdateBanner`, `UpdateAvailableBanner`, `CruxUpdateBannerMetrics` | The banner: a `ConsumerStatefulWidget` gate you mount above your routed content, and the dumb leaf strip it renders. |
| `runManualUpdateCheck(context, ref)` | The manual "Check for Updates" action, with its in-flight / up-to-date / failed toasts. |
| `kUpdateCheckTimeout`, `kUpdateCheckInterval` | The defaults `CruxUpdateConfig` starts from. |

### Providers a product overrides

| Provider | Default | Override with |
|---|---|---|
| `cruxUpdateConfigProvider` | **Throws** `UnimplementedError` | Your `CruxUpdateConfig`. |
| `cruxUpdateStringsProvider` | English, named after `config.productName` | Your `AppLocalizations` adapter. |
| `updateBuildInfoProvider` | `null` (⇒ no-op service) | Your `applicationBuildInfoProvider`. |
| `autoUpdateCheckEnabledProvider` | `true` | Your persisted "automatically check for updates" setting. |
| `observedServerTimeSinkProvider` | no-op | Your persisted server-time store (feeds `crux_license`). |
| `updateEditionProvider` | `UpdateEdition.unlocked` (every release offered) | `UpdateEdition.of(paidFeaturesUnlocked: …)`, computed with the same gate your paid features use. |
| `updateUrlLauncherProvider` | **Throws** on use | `url_launcher`'s `launchUrl`. |
| `updateHttpClientProvider` | a fresh `http.Client` | A `MockClient`, in tests. |

Only two of the eight have no working default, and both are deliberate:
a product that forgets its `CruxUpdateConfig` fails at wiring, not
silently three weeks after a release, and a product that forgets the URL
launcher gets a loud failure rather than a dead "Update Now" button.

## Wiring it in (per product)

```dart
// 1. The product's configuration — one instance, usually a top-level final.
final netCruxUpdateConfig = CruxUpdateConfig(
  productName: 'NetCrux',
  manifestUri: 'https://updates.netcrux.app/manifest.json',
  downloadPageUri: 'https://netcrux.app/download',
  // appStoreUri / playStoreUri only if the product ships on mobile.
);

// 2. An adapter bridging the product's AppLocalizations to the package
// strings interface (the LicenseBadgeStrings pattern).
class NetCruxUpdateStrings extends CruxUpdateStrings {
  const NetCruxUpdateStrings(this._l10n);
  final L10N _l10n;

  @override String bannerMessage(String version) =>
      _l10n.updateBannerMessage(version);
  @override String get viewChangesAction => _l10n.updateViewChangesAction;
  @override String get updateNowAction => _l10n.updateNowAction;
  @override String get dismissLabel => _l10n.updateDismissLabel;
  @override String get checkInProgress => _l10n.updateCheckInProgress;
  @override String checkUpToDate(String v) => _l10n.updateCheckUpToDate(v);
  @override String get checkFailed => _l10n.updateCheckFailed;
}

// 3. The root ProviderScope overrides.
ProviderScope(
  overrides: [
    cruxUpdateConfigProvider.overrideWithValue(netCruxUpdateConfig),
    updateBuildInfoProvider.overrideWith(
      (ref) => ref.watch(applicationBuildInfoProvider.future),
    ),
    autoUpdateCheckEnabledProvider.overrideWith(
      (ref) async =>
          (await ref.watch(appSettingsProvider.future)).autoCheckForUpdates,
    ),
    observedServerTimeSinkProvider.overrideWith(
      (ref) => ref.read(observedServerTimeStoreProvider.notifier).record,
    ),
    // Watched, not read once: a key entered mid-session re-presents the last
    // check's result under the new edition.
    updateEditionProvider.overrideWith(
      (ref) => UpdateEdition.of(
        paidFeaturesUnlocked:
            ref.watch(betaPeriodProvider) ||
            FeatureGate.satisfiesTier(
              LicenseTier.pro,
              ref.watch(licenseTierProvider),
            ),
      ),
    ),
    updateUrlLauncherProvider.overrideWithValue(launchUrl),
  ],
  child: const NetCruxApp(),
);

// 4. Mount the banner above the routed content, inside MaterialApp so the
// host's localization delegates resolve. Nest it *inside* any beta-expiry
// gate so a blocking expiry modal covers the banner.
MaterialApp.router(
  // ...
  builder: (context, child) => BetaExpiryGate(
    child: UpdateBanner(
      metrics: CruxUpdateBannerMetrics(
        touchTarget: metrics.touchTarget,
        iconSize: metrics.iconSize,
        bodyFontSize: metrics.bodyText,
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  ),
);

// 5. Wire the manual action (Help menu / command palette / About box).
onPressed: () => runManualUpdateCheck(context, ref),
```

The strings adapter must supply the product name itself —
`bannerMessage` receives only the version, because the product's own ARB
string ("NetCrux {version} is available.") is where the name belongs.
`CruxUpdateStringsEn` fills the name from `config.productName` so an
un-localized build still reads correctly.

## Manifest format

```json
{
  "latest": {
    "version": "1.2.0",
    "channel": "stable",
    "release_date": "2026-09-15",
    "changelog_url": "https://netcrux.app/releases/1.2.0",
    "mandatory": false,
    "min_supported_version": "1.0.0",
    "open_core_version": "1.1.0",
    "downloads": { "macos_universal": "…", "windows_x64": "…" },
    "checksums": { "macos_universal": "sha256:…" },
    "server_time": "2026-09-15T12:00:00Z"
  }
}
```

Only `version` is required; everything else has a benign default, and a
type-mismatched field is dropped rather than fatal. `downloads` and
`checksums` are parsed and retained for a future in-place-update
transport — today the banner deep-links to the download page.

## Releases that change only paid features

Each product ships **one** desktop binary, and a licence key unlocks paid
features in place. A user who never buys runs the same build a paying
customer does — so a release whose every change sits behind a paid-tier
gate is still "newer" for them, and would put an update banner in front of
the free majority for a build with nothing in it they can use.

`open_core_version` fixes that. It names the **newest release that changed
what a seat without paid features gets**:

- A release with any such change sets it to its own `version`.
- A release whose every change is behind a paid-tier gate leaves it at the
  previous value.
- It never decreases, and never exceeds `version`.

The client rule, `UpdateEdition.offers`:

| Seat | Offered the newer `latest` when |
|---|---|
| `unlocked` — Pro, Educational, Enterprise, or any tier during a beta period | always |
| `openCore` — no paid features unlocked | the running build is older than `open_core_version`, **or** the release is mandatory |

What is offered is always `latest` itself, never an older release, because
`latest` carries every earlier change. That is why this is a version and not
a per-release "paid features only" flag: with `latest` = 1.1.1 (paid only)
and `open_core_version` = 1.1.0, a free seat still on 1.0.0 is offered 1.1.1
— it needs 1.1.0's change — while a free seat on 1.1.0 is offered nothing. A
flag on 1.1.1 alone would have hidden 1.1.0's change from the 1.0.0 seat.

Properties worth stating, because each is load-bearing:

- **It only ever withholds, and only from an `openCore` seat.** No path
  produces an offer the unfiltered check would not have made.
- **Mandatory always wins.** That includes a build below
  `min_supported_version`, which the check marks mandatory before the rule
  runs. A security fix or an end of support applies to every seat.
- **Missing or unparseable means offer.** A manifest without the field, or
  with one the client cannot read, behaves exactly as before the field
  existed. A build that predates the field ignores it the same way.
- **The fetch still happens.** The rule is applied to the result, so a
  withheld seat still reports `server_time`.
- **A licence change takes effect at once.** `updateStatusProvider` keeps the
  last release the check returned and re-applies the rule whenever
  `updateEditionProvider` changes, with no second fetch. A user who has just
  entered a key sees the release their build was being withheld.

## Behavior contract

- **A failed check never breaks a feature flow.** The service throws
  exactly one typed `UpdateCheckException`; the notifier maps it (and any
  unexpected raw error) to `UpdateStatusError`. Nothing escapes.
- **The banner never nags on failure.** `checking` and `error` render
  nothing; only the manual action reports a failed check.
- **`min_supported_version` is a floor, not a filter.** A newer release
  always surfaces. When the running build is *below* the floor, the
  update is forced `mandatory: true` even if the manifest does not say
  so — a build below the floor is no longer supported.
- **`mandatory` means non-dismissible.** No close affordance is rendered.
- **A dismissal lasts the session, per version.** Dismissing 1.2.0 hides
  the strip until a *newer* version is offered.
- **An `openCore` seat is offered only releases that concern it.** See
  [Releases that change only paid features](#releases-that-change-only-paid-features).
- **`server_time` is reported on every successful fetch**, including when
  the running build is already current, and before the newer/floor gate.
  It feeds `crux_license`'s `observedServerTimeProvider`, which is what
  makes beta expiry resistant to a device-clock rollback. This is why the
  update check still runs on web, where the banner never renders.
- **Auto vs manual.** Launch, periodic and on-resume checks all run
  through `runScheduledCheck()` and honor
  `autoUpdateCheckEnabledProvider`. `checkNow()` ignores it — a manual
  check always runs.
- **Mobile is opt-in.** iOS/Android get `NoopUpdateCheckService` unless
  `checkOnMobile` is set: store builds update through the store, and
  skipping the fetch keeps the "Data Not Collected" privacy declaration
  true. Desktop and web get the live service.
- **The web build never shows the banner.** A web app self-updates on
  deploy, so a "download the new version" strip is noise; the check
  itself still runs for the `server_time` watermark.

## Enterprise: managed installs and policy constraints

Two separate mechanisms, deliberately, and the order between them is the
whole point.

**A managed install** — MSI, `.deb`, `.rpm` — is detected from a
`.managed-install` marker file the package lays down beside the
executable. The organization's deployment tooling owns the version, so
the app issues **no manifest fetch at all** and shows nothing. This is
checked first and **outranks every policy key**: it describes how the app
was installed, not what an administrator configured, and inverting the
order would let `updateChannel: stable` silently re-enable self-update
across an SCCM-managed fleet.

**Policy constraints** come from the signed `.crux-policy.json` and are
read only after that. Three optional keys, each defaulting to
unconstrained:

| Key | Effect |
|---|---|
| `suite.updateChannel` | `stable` offers stable releases only · `beta` offers stable + beta · `pinned` offers nothing newer than the pin |
| `suite.pinnedVersion` | The ceiling under `pinned`. Inert without it |
| `suite.manifestUrl` | An on-prem mirror to fetch instead of the product's endpoint |

`pinned` is a **ceiling, not an equality test**, which is what lets it
compose with `manifestUrl`: a mirror advertising 1.4.0 to a fleet pinned
at 1.4.0 still updates a seat that is back on 1.2.0.

The package never reads the policy file — it does not know the format,
where it lives, or how its signature is verified. It takes the answer
through `updatePolicyProvider`, and each Pro overlay binds it in one
override (see `UpdatePolicy.fromNames`).

Two properties worth stating, because both are load-bearing:

- **Constraints only ever withhold.** No path can produce an offer the
  unconstrained check would not have made.
- **A constrained seat still fetches.** Filtering happens *after* the
  request, so a pinned or stable-channel machine keeps contributing the
  `server_time` observation that hardens beta expiry against a device
  clock set backwards. Skipping the fetch would have handed every
  Enterprise seat a way to stop that clock.

## What the check transmits

One `GET` for a public JSON file, with a single `User-Agent` header of
the form `NetCrux/1.2.0 (macOS 15.0)`. No file, design, netlist,
waveform or identity data — ever. There is no telemetry surface in this
package.

## Localization

Like every `crux_shared` package, this one contains **no ARB files**.
`CruxUpdateStrings` is the seam; each product maps it onto its own
generated localizations and owns the five-locale (en/zh_CN/zh/ja/ko)
parity sweep. The package's own widget tests sweep string sets,
directionality and text scale instead of locales — a per-locale ARB
sweep is meaningless without ARB files, and it is the consuming
product's responsibility.

## Status

Stable as of 0.1.0. `crux_updates` deliberately does **not** contain:

- **Any download/install transport.** "Update Now" opens a URL. In-place
  download, checksum verification and relaunch are a later item — the
  manifest already carries `downloads` and `checksums` for it.
- **Any notion of who may use a channel.** `suite.updateChannel` is an
  administrator's configuration, not an entitlement: this package neither
  knows nor asks what tier a seat holds. Publishing to a channel is the
  release side's job.
- **Any notion of a licence tier.** `updateEditionProvider` takes the answer
  to one question — are paid features unlocked on this seat? — and the
  product computes it. No shared package outside `crux_license` branches on
  a paid tier.
- **The persisted observed-server-time store.** The package emits the
  observation through `observedServerTimeSinkProvider`; persistence
  belongs to the host, which already owns a preferences layer.

## Visibility & license

Private during the public beta. Apache 2.0 at the post-beta open-core
flip, alongside every product's open-core repo. Consumed by each
product's open-core via the `crux-shared` Git submodule plus a `path:`
dep; the Pro overlays inherit it transitively.
