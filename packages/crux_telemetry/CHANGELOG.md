# Changelog

## Unreleased

- **The consent disclosure is reachable and operable from the keyboard and a
  screen reader.** It was stacked over the app with only a barrier, so on a
  first launch focus stayed on the hidden app: Tab walked its controls (each
  one silent), nothing ever landed in the disclosure, and Enter could press a
  button behind it. `TelemetryConsentGate` now mounts it through
  `crux_a11y`'s `CruxModalGate`, which keeps the app out of focus and
  semantics while the disclosure is up and moves focus to the app's first
  control once it is answered. The disclosure is a `CruxModalSurface`
  announced by its title, focus opens on the disclosure text so it is read
  before any control, Tab cycles through the link, the switch and Continue
  without leaving it, and Escape does not dismiss it. `crux_a11y` is a new
  dependency.

- **The docs name the right gate.** `telemetryGateProvider` is the
  transmission gate — `telemetryServiceProvider` chooses the live, no-op or
  pending service from it alone — and now carries the precedence
  documentation.
  `telemetryEnabledProvider` had carried it, and the package barrel, the
  README and four doc comments called it the gate, but nothing in the pipeline
  watches it: it is `gate == open` as a `bool`, kept for tests and
  diagnostics, and it reads `pending` as `false`. No behaviour changes.

- **`app.uncaught_error`: a crash counter, recorded for every product.**
  `TelemetryUncaughtErrorCounter` counts an uncaught error once per
  `(source, kind, library)` tuple per session, at most
  `kTelemetryUncaughtErrorSessionCap` (10) tuples, with four closed-vocabulary
  properties — `source`, `kind`, `library`, `silent` — and never the message,
  the stack or a file name. `kind` is bucketed by `is` checks
  (`telemetryErrorKindOf`), never by `runtimeType.toString()`, which an
  obfuscated release build scrambles; `library` maps
  `FlutterErrorDetails.library` onto the names the framework emits
  (`telemetryErrorLibraryOf`), and a test reads the resolved Flutter SDK so a
  new one cannot slip through as `other`.

  `telemetryServiceProvider` attaches the counter to whichever service it
  resolves, so consent is decided by the existing gate; errors from before the
  container existed wait in a buffer bounded by the session cap and are then
  handed to that service. The counter is inert in a build that cannot
  transmit. `crux_issue_reporter`'s `captureFlutterErrors` feeds it, so a
  product wires nothing new — it only lists the event in its catalog.

- **The default consent copy names error counts.** `consentBody` and
  `settingsToggleDescription` in `CruxTelemetryStringsEn` now say "usage and
  error counts" and "Feature-usage and error counts only", and the settings
  line adds error messages to what is never sent.

## 0.5.0

- **Settings → Privacy now shows the installation ID**, with a copy button.

  The privacy policy promises a deletion path: send us your installation id
  and we delete the rows carrying it. Nothing collected is tied to a person,
  so that id is the *only* handle — and until now `telemetryInstallationIdProvider`
  held the value and nothing displayed it, so the promised path could not be
  walked. A walkable deletion path is a prerequisite for activating
  telemetry; this closes it.

  Found the honest way: the disclosure page says the id is in Settings →
  Privacy, and someone went to look.

## 0.4.0

Added:

- **`'vscode'` in `kTelemetryFormFactors`.** The bucket for a build running
  inside an editor host — a VSCode webview or a VSCode extension host — rather
  than a browser tab or a native window. Purely additive; no existing consumer
  changes behaviour.

  It exists because `kIsWeb` is **true inside a VSCode webview**, so without it
  every EDACrux extension user would report `form_factor: 'web'`, breaking two
  numbers at once: extension adoption would be unmeasurable, and the
  `web`-vs-`desktop` split — which exists to answer "does the web build earn
  its maintenance" — would silently absorb extension traffic and read as fact
  forever after. `os` stays `'web'`, which remains honest.

  **Deployment order is load-bearing.** `kTelemetryFormFactors` is the
  vocabulary the ingestion Worker's `FORM_FACTORS` enforces, and an unknown
  bucket rejects the *whole batch* with a 400 the client never sees. The Worker
  must accept `'vscode'` before any editor-hosted build reports it.

## 0.3.0

The three defects the suite's cross-platform end-to-end pass found
(WaveCrux `verification/VERIFICATION_CHECKLIST.md` §13A.3). All three had
passed every automated gate in this package, which is the more
interesting half of each entry.

Added:

- `CruxTelemetryConfig.volatileFlushInterval` and
  `kTelemetryVolatileFlushInterval` (60 s) — the flush cadence used
  **only** where the queue has no persistent backing.
- `TelemetryEventQueue.hasPersistentBacking()` — asked rather than
  inferred from an empty `load()`, which a healthy first launch on disk
  also returns.
- `TelemetryLifecycleObserver` and `observeTelemetryLifecycle` — the
  hidden/paused/detached seam, built on Flutter's `AppLifecycleListener`
  so no `dart:html` dependency enters the package.
- `LiveTelemetryService.isVolatile`, for tests.

Changed:

- **Web never transmitted.** With a memory-only queue the launch
  flush ships the previous session, which on web is always empty, so it
  returned at `_pending.isEmpty` having armed nothing; the only surviving
  trigger was a six-hourly timer no browser session outlives. Four
  products' web builds sent zero rows. In volatile mode `record()` now
  arms one flush per `volatileFlushInterval` window — per window, not per
  event, so a steadily recording session still progresses — a flush that
  skipped on an unresolved envelope re-arms, and the host's
  hidden/paused/detached signal flushes. **The persistent-queue contract
  is unchanged**: desktop and mobile keep "the launch flush ships the
  previous session, then every six hours", because there the file is the
  handover and there is a next launch to rely on.
- **`form_factor` raced the first layout.** A Pixel Tablet held in
  portrait reported `desktop` on three of four launches. The envelope
  resolves at flush time, ahead of the display size a product pushes from
  `MaterialApp.builder`, so the hook answered from its pre-layout
  default. `telemetryFormFactorProvider` is now `Provider<String?>` and
  `resolveTelemetryEnvelope` returns `null` when it is `null` — the same
  defer-and-retry the unresolved `app_version` already got, and for a
  sharper reason: a bad `app_version` is rejected by the Worker, whereas a
  bad `form_factor` is accepted and silently books mobile installations as
  desktop. A derivation that cannot race must still return a value; the
  package default is unconditional and unchanged.
- A flush the envelope resolver **deferred** now retries after
  `volatileFlushInterval` on **every** host, not only a volatile one.
  That is not a cadence — it is the same flush, finished late, carrying
  the events it was already carrying, so nothing goes out inline with the
  event that produced it. Without it the `form_factor` fix would have broken
  mobile the way the memory-only queue broke web: the launch flush loses the first-frame race, and
  the "next tick" that picks the queue up is six hours away or a next
  launch that races the same frame again.
- **A stored `disabled` transmitted under the dev flag.**
  `TelemetryConsentStore` publishes `unset` synchronously and loads
  asynchronously, so on a cold start a refusal and "not answered yet" are
  the same value — and the dev flag promotes "not answered yet" to
  consent. `telemetryEnabledProvider` now gates that promotion on
  `telemetryConsentReadyProvider`, the `loaded` signal the disclosure
  already waits on. Shipping builds were never affected (with `dev` off
  the beta branch short-circuits, and post-flip the test is
  `consent == enabled`, which `unset` fails safe), but the guarantee the
  dev flag documents was broken.
- **The gate is a tri-state**, `TelemetryGate { open, closed, pending }`,
  exposed as `telemetryGateProvider`; `telemetryEnabledProvider` is
  `gate == open` and its meaning is unchanged. `pending` exists because
  gating on the consent load creates a window, and the window is not incidental: the
  consent store's read does not *start* until something reads the
  telemetry graph, so the first event of every launch — on all four
  products, `workspace.restored` from a notifier's `build` — falls inside
  it by construction. Resolving `NoopTelemetryService` there does not
  defer that event, it deletes it, and on web a passive session records
  nothing else at all. `PendingTelemetryService` buffers instead, capped
  at `maxQueuedEvents`, and the buffer is replayed into the live service
  when the gate opens or dropped when it closes. Nothing leaves the
  machine from the pending state. **The beta never enters it**: the
  dark-launch branch answers `closed` synchronously, so a beta build
  holds no telemetry in memory any more than it sends any.
- The 36-cell gating matrix now settles the store before asserting, and a
  new **pre-load window** group seeds consent through *storage* behind a
  gated read. Every one of the 36 cells seeded `notifier.state` directly,
  which is synchronous, so none of them ever opened the window the refusal
  leaked through. That gap, not the gate expression, is what let a real installation
  transmit against its own recorded refusal.

## 0.2.0

Telemetry's half of the Enterprise policy contract. The
`.crux-policy.json` **loader** is not here and is not part of this
release: it depends on the `crux_license` Ed25519 JWT validator that is
still `NoopLicenseValidator`, and an unsigned policy file would be
self-granting. What lands is the behaviour that loader will select, so
binding it is one override against something already implemented and
already tested.

Added:

- `TelemetryPolicy` — `allow` / `deny` / `absent`. `absent` is every
  non-Enterprise installation, any Enterprise one without the key, and
  the default everywhere.
- `telemetryPolicyProvider` — the seam, defaulting to
  `TelemetryPolicy.absent`. Nothing in the suite overrides it yet.

Changed:

- `telemetryEnabledProvider` is now beta × dev × **policy** × consent.
  `deny` never collects and `allow` always does, both beating the stored
  consent — the seat's machine and licence are the organisation's, and
  the decision sits with the admin so it is uniform across a fleet.
  The beta gate still beats both: the store privacy declarations ship in
  the flip release, so a policy file can decide *whether* we collect but
  not *when* collection starts.
- `telemetryConsentUiVisibleProvider` is `false` under either policy
  value, which retires **both** consent surfaces — the first-launch
  disclosure and the Settings → Privacy toggle. Individual engineers on a
  managed seat do not see a telemetry prompt, and a toggle the gate ignores
  is worse than no toggle.
- A policy **never writes the consent store**. It is a runtime decision,
  not a recorded choice; remove the key and the installation falls back
  to whatever the engineer actually chose (usually `unset`, which
  prompts).
- The gating matrix in `telemetry_service_provider_test.dart` is now all
  36 policy × beta × dev × consent cells, and the beta-inert traffic test
  sweeps policy as well as consent.

## 0.1.0

Initial release. The shipped WaveCrux telemetry pipeline, lifted into a
product-agnostic package. WaveCrux migrated onto it in the same change;
NetCrux, LintCrux and SimCrux adopt it next.

Added:

- `CruxTelemetryConfig` — the per-product configuration that replaces
  WaveCrux's hardcoded `kTelemetryProduct = 'wavecrux'` and its
  `WaveCrux/$version` User-Agent: product slug, User-Agent name, the two
  ingest endpoints, the disclosure URL, and the queue/flush tuning, plus
  `endpointFor(dev:)`.
- `CruxTelemetryStrings` + `CruxTelemetryStringsEn` — caller-supplied
  localization surface for both consent surfaces, following the
  `CruxUpdateStrings` pattern. Both list blocks are required members
  rather than nullable extras.
- `TelemetryEvent`, `TelemetryService`, `NoopTelemetryService`,
  `LiveTelemetryService`, `TelemetryEventQueue`, the coalescing batcher,
  `TelemetryEnvelope` and `telemetryEnumToken` — moved unchanged in
  behavior from the WaveCrux originals, with every doc comment retained.
- `TelemetryConsentState` + `TelemetryConsentStore`, and the gate:
  `telemetryEnabledProvider` (`kBetaPeriod` × `TELEMETRY_DEV` ×
  consent), `telemetryConsentUiVisibleProvider`,
  `telemetryConsentReadyProvider`,
  `telemetryConsentPromptVisibleProvider`.
- `TelemetryStorage` + `InMemoryTelemetryStorage` + the two suite-fixed
  keys — the persistence seam that replaces WaveCrux's direct
  `SharedPreferences` reads.
- `TelemetryConsentGate`, `TelemetryConsentDisclosure`,
  `TelemetrySettingsSection`, `CruxTelemetryConsentMetrics` and
  `kTelemetryConsentMinTarget` — both consent surfaces, string- and
  metrics-parameterized.
- `test/fixtures/valid-batch.json` — the canonical Worker payload
  contract, and the test that asserts this package's serializer emits it
  key-for-key.

Deviations from the WaveCrux original, all forced by the extraction:

- **Persistence is a seam, not `SharedPreferences`.** WaveCrux read the
  plugin directly from `TelemetryConsentStore` and
  `telemetryInstallationIdProvider`; both now go through
  `telemetryStorageProvider`. The storage *keys* stayed in the package,
  because the suite spec fixes them and four products have to agree.
  `TelemetryConsentStore.prefsKey` is now `storageKey` — the old name
  described a plugin the package no longer knows about.
- **Hand-written Riverpod providers.** No package here uses
  `build_runner`, so the `@Riverpod` codegen the WaveCrux original relied
  on for the consent store and the installation id was dropped rather
  than introduced into `crux-shared`.
- **The app version is an injectable `FutureProvider<String?>`** rather
  than a read of a product's `applicationBuildInfoProvider`. The `null`
  default preserves the original behavior exactly: a flush that races
  startup skips rather than inventing a version the Worker would reject.
- **`form_factor` is a provider seam.** The `DeviceClass → bucket`
  mapping is WaveCrux's own layout vocabulary and stayed there; the
  package keeps only the closed `kTelemetryFormFactors` list the mapping
  must land in.
- **The disclosure takes `isPhoneLayout` and
  `CruxTelemetryConsentMetrics`** instead of WaveCrux's `DeviceClass` and
  `MobileMetrics`, following `CruxUpdateBannerMetrics`. The 44 dp floor
  is now applied by the widget (`effectiveTouchTarget`) rather than by
  each caller, so a host that passes a 28 dp desktop target still gets a
  reachable "off".
- **URL launching is its own seam.** WaveCrux routed the disclosure link
  through `crux_updates`' `updateUrlLauncherProvider` because that was
  the launcher that already existed; `telemetryUrlLauncherProvider` is
  the same bare `Future<bool> Function(Uri)` under a name that describes
  its caller.
- **The event catalog did not come.** `kWavecruxEventCatalog`, its
  conformance test, and every instrumentation call site stayed in
  WaveCrux. A catalog is the one part of telemetry that cannot be shared.
