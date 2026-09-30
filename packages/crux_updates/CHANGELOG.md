# Changelog

## Unreleased

- **Releases that change only paid features are no longer offered to seats
  without them.** Each product ships one binary, and a licence key unlocks
  paid features in place, so a paid-only release used to put an update banner
  in front of every free user for a build with nothing in it for them.
  - The manifest gains `open_core_version`: the newest release that changed
    what a seat without paid features gets. `UpdateInfo.openCoreVersion` and
    `UpdateInfo.changesOpenCoreSince` read it.
  - New `UpdateEdition` (`unlocked` / `openCore`) and `updateEditionProvider`,
    defaulting to `unlocked`, which offers every release exactly as before.
    Products bind it with `UpdateEdition.of(paidFeaturesUnlocked: …)`.
  - An `openCore` seat is offered `latest` only when its build is older than
    `open_core_version` or the release is mandatory (including a build below
    `min_supported_version`). Missing or unparseable values offer.
  - Applied in `UpdateStatusNotifier`, not in the service graph: the notifier
    keeps the last release the check returned and re-applies the rule when the
    edition changes, so a licence entered or lapsing mid-session takes effect
    without a second fetch. The fetch still runs for an `openCore` seat, so
    `server_time` is still observed.

## 0.1.0

Initial release. The shipped WaveCrux update-check mechanism, lifted into
a product-agnostic package for NetCrux, LintCrux and SimCrux (WaveCrux
itself has not migrated yet).

Added:

- `CruxUpdateConfig` (+ `CruxUpdateConfig.fromUris`) — the per-product
  configuration that replaces WaveCrux's hardcoded manifest URL and
  `WaveCrux/$version` User-Agent: manifest URI, product display name,
  download page, optional App Store / Play Store URIs, `checkOnMobile`,
  fetch timeout and auto-check interval, plus
  `updateTargetFor(platform, {isWeb})`.
- `CruxUpdateStrings` + `CruxUpdateStringsEn` — caller-supplied
  localization surface, following the `LicenseBadgeStrings` /
  `CruxAboutStrings` pattern. Version interpolation is a method, not a
  format template.
- `UpdateInfo` / `UpdateManifest` — fail-soft manifest model with semver
  comparison (`isNewerThan`, `meetsMinSupported`) and the `server_time`
  field that feeds `crux_license`'s beta-expiry clock hardening.
- `UpdateStatus` sealed hierarchy (`current` / `checking` / `available` /
  `error`).
- `UpdateCheckService` + `UpdateCheckException` seam;
  `HttpUpdateCheckService` (live manifest fetch) and
  `NoopUpdateCheckService` (always current).
- `updateStatusProvider` / `UpdateStatusNotifier` — launch check,
  periodic timer, gated `runScheduledCheck()`, always-on `checkNow()`.
  Hand-written Riverpod providers: no package here uses `build_runner`,
  so the codegen the WaveCrux original relied on was dropped rather than
  introduced into `crux-shared`.
- `updateCheckServiceProvider` — live service on desktop/web once build
  info resolves; no-op on mobile store builds and before build info
  loads.
- Overridable seams: `cruxUpdateConfigProvider` (no default — throws),
  `cruxUpdateStringsProvider`, `updateBuildInfoProvider`,
  `autoUpdateCheckEnabledProvider`, `observedServerTimeSinkProvider`,
  `updateUrlLauncherProvider` (no working default — throws),
  `updateHttpClientProvider`.
- `UpdateBanner` + `UpdateAvailableBanner` + `CruxUpdateBannerMetrics` —
  the dismissible update strip, non-dismissible when `mandatory`, hidden
  on web, with host-supplied sizing in place of any product's device
  metrics.
- `runManualUpdateCheck(context, ref)` — the manual "Check for Updates"
  action with in-flight / up-to-date / failed toasts.

Deviations from the WaveCrux original, all forced by the extraction:

- The persisted observed-server-time store (`SharedPreferences`-backed in
  WaveCrux) is **not** here. The package emits observations through
  `observedServerTimeSinkProvider`; the host owns persistence and the
  hand-off to `crux_license`'s `observedServerTimeProvider`.
- URL launching is a provider seam instead of a mutable top-level
  `launchUrl` alias, so the package takes no `url_launcher` dependency.
- The auto-check setting is an injectable `FutureProvider<bool>` rather
  than a read of a product's settings model; `crux_settings`'
  `CoreSettings` carries no `autoCheckForUpdates` field, so it is not the
  right seam.
- Mobile is skipped by default exactly as WaveCrux does, but a product
  can opt back in with `CruxUpdateConfig.checkOnMobile`.
- The manual check now shows a transient "Checking for updates…" toast
  that the outcome replaces; WaveCrux showed nothing until the check
  resolved.
- `SemanticVersion` is package-internal and not exported — the name is
  too generic for a shared barrel, and products already carry their own.
