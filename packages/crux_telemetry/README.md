# crux_telemetry

Cross-suite anonymous usage-statistics pipeline for the EDACrux suite —
WaveCrux, NetCrux, LintCrux and SimCrux.

One implementation of "what did people actually use, and did they agree to
tell us?": the event model, the append-only disk queue with its age and
size caps, the coalescing batcher that matches the ingestion Worker's
payload contract, the never-throwing ingest client with its backoff, the
beta × dev-flag × Enterprise-policy × consent gate, and both consent
surfaces.

Everything product-specific arrives through configuration or an
overridable provider — the product slug, the `User-Agent` name, the
localized copy, the `form_factor` derivation, the persistence adapter —
so the package itself knows nothing about any one product. It contains
**no event catalog**: the catalog and the call sites that record against
it are the one part of telemetry that is genuinely per-product. The one
event it records itself is `app.uncaught_error` — see
[The uncaught-error counter](#the-uncaught-error-counter) — and each
product still lists that in its own catalog.

Extracted from the shipped WaveCrux implementation, which is its first
consumer.

## The one thing to know first

**The pipeline is inert for the whole public beta.**
`telemetryGateProvider` — the gate, from which alone
`telemetryServiceProvider` chooses the live, no-op or pending service — is
`closed` for every consent value **and every Enterprise policy value**
while `crux_license`'s `kBetaPeriod` is on and the `TELEMETRY_DEV`
dart-define is off. The live service is therefore never constructed, no
consent surface mounts, and zero HTTP requests leave the build. Activation
is the `kBetaPeriod` flip, not a merge — the store privacy declarations
ship in that same release.

`test/src/providers/telemetry_service_provider_test.dart` asserts this
against *traffic*, not against a class name, across all three consent
values × all three policy values. If that test goes red, a beta build is
transmitting.

## Surface

| Symbol | Purpose |
|---|---|
| `CruxTelemetryConfig` | The per-product configuration: `productSlug` (the `product` envelope field), `userAgentName`, the two endpoints, the disclosure URL, and the queue/flush tuning. `endpointFor(dev:)` picks the dataset. |
| `CruxTelemetryStrings` / `CruxTelemetryStringsEn` | Caller-supplied localization surface for both consent surfaces. Both list blocks are required members — a disclosure that shows one list without the other is an advertisement. |
| `TelemetryEvent` | The recorded event: name, scalar properties, timestamp. The timestamp ages the queue and is never transmitted. |
| `TelemetryService`, `NoopTelemetryService`, `LiveTelemetryService`, `PendingTelemetryService` | The seam and its three implementations. The live one never throws and never blocks the UI isolate; there is no error channel out of it at all. The pending one buffers, and only for the window where consent is not knowable yet. |
| `TelemetryGate`, `telemetryGateProvider` | The gate: `open` / `closed` / `pending`, and the one provider `telemetryServiceProvider` watches. The third value exists because "not yet" must not discard the launch counter. |
| `telemetryEnabledProvider` | `gate == open`, as a `bool`, for tests and diagnostics. Nothing in the pipeline watches it, and it reads `pending` as `false` — ask the gate whether an event recorded now is kept. |
| `TelemetryEventQueue`, `pruneTelemetryEvents` | JSON-Lines queue at `{appSupportDir}/telemetry_queue.jsonl`, capped at 2000 events / 7 days, memory-only where `path_provider` is unavailable. `hasPersistentBacking()` is what the service asks to pick its cadence. |
| `TelemetryLifecycleObserver`, `observeTelemetryLifecycle` | The hidden/paused/detached seam, used **only** in volatile mode. Flutter's own `AppLifecycleListener`, never `dart:html`. |
| `TelemetryBatchEntry`, `coalesceTelemetryEvents`, `buildTelemetryBatches`, `encodeTelemetryBatch` | Coalescing (identical name + properties fold into one `count`) and splitting at the Worker's 500-event / 64 KB caps. |
| `TelemetryEnvelope`, `telemetryIso8601` | The per-batch envelope and its exact key order. |
| `TelemetryConsentState`, `TelemetryConsentStore` | The tri-state decision and its persisted store. `unset` is not `disabled`. |
| `TelemetryPolicy` | The Enterprise administrator's org-wide decision — `allow`, `deny`, `absent`. `absent` is every non-Enterprise installation and the default. This package never reads the policy *file*; see "The Enterprise policy seam". |
| `TelemetryStorage`, `InMemoryTelemetryStorage`, `kTelemetryConsentKey`, `kTelemetryInstallationIdKey` | The two-method persistence seam and the suite-fixed keys. |
| `telemetryInstallationIdProvider`, `mintTelemetryInstallationId` | A random v4 UUID per installation, never a host fingerprint. |
| `telemetryEnumToken` | `Enum` → `[a-z0-9_]` token. Takes an `Enum`, not a `String`, on purpose. |
| `TelemetryUncaughtErrorCounter`, `telemetryUncaughtErrorCounterProvider`, `kTelemetryUncaughtErrorSessionCap` | The `app.uncaught_error` counter the global error handlers report to, and the seam `telemetryServiceProvider` attaches it through. See [The uncaught-error counter](#the-uncaught-error-counter). |
| `kTelemetryUncaughtErrorEvent`, `kTelemetryUncaughtErrorSources` / `Kinds` / `Libraries`, `kTelemetryFlutterLibraryTokens`, `telemetryErrorKindOf`, `telemetryErrorLibraryOf` | That event's name and closed vocabulary, and the two classifiers that land every error inside it. |
| `telemetryOsSlug` / `telemetryOsSlugFor`, `kTelemetryOperatingSystems`, `kTelemetryFormFactors`, `kTelemetryLicenseTiers` | The closed envelope vocabularies the Worker enforces. |
| `TelemetryConsentGate`, `TelemetryConsentDisclosure`, `TelemetrySettingsSection`, `CruxTelemetryConsentMetrics`, `kTelemetryConsentMinTarget` | The two consent surfaces and their sizing. |
| `kTelemetryDev`, `telemetryEndpointFor`, `kTelemetryProductionEndpoint`, `kTelemetryStagingEndpoint`, `kTelemetryDocumentationUri` | The dark-launch flag and the suite endpoints. |

### Providers a product overrides

| Provider | Default | Override with |
|---|---|---|
| `cruxTelemetryConfigProvider` | **Throws** `UnimplementedError` | Your `CruxTelemetryConfig`. |
| `cruxTelemetryStringsProvider` | English, named after `config.userAgentName` | Your `AppLocalizations` adapter (from inside `MaterialApp.builder`). |
| `telemetryStorageProvider` | `InMemoryTelemetryStorage` | A four-line adapter over your preferences layer. |
| `telemetryUrlLauncherProvider` | **Throws** on use | `url_launcher`'s `launchUrl`. |
| `telemetryAppVersionProvider` | `null` (⇒ flush skips) | Your build info's `version`. |
| `telemetryFormFactorProvider` | `'desktop'` | Your own layout-idiom mapping. Return **`null`** if it is not knowable yet (⇒ flush skips and retries), never a guess. |
| `telemetryLocaleProvider` | `'en'` | Your resolved app locale. |
| `telemetryHttpClientProvider` | a fresh `http.Client` | A `MockClient`, in tests. |
| `telemetryPolicyProvider` | `TelemetryPolicy.absent` | An Enterprise overlay, from its `.crux-policy.json` loader. Nothing overrides it today. |
| `telemetryDevModeProvider` / `telemetryBetaPeriodProvider` | `kTelemetryDev` / `kBetaPeriod` | Only in tests — these are the gate. |
| `telemetryEnvelopeResolverProvider` | assembles the envelope | Only if a product needs an envelope this package does not model. |

Two of these have no working default, and both are deliberate: a product
that forgets its `CruxTelemetryConfig` fails at wiring rather than
reporting somebody else's slug forever, and a product that forgets the
URL launcher gets a loud failure rather than a dead "Learn more" link on
a privacy disclosure.

`telemetryStorageProvider` is the exception that proves the rule. It
defaults to a working in-memory store rather than throwing, because
telemetry code may not throw into a feature flow — the failure mode of
forgetting it (the disclosure re-prompts every launch) is the loudest
thing available that still cannot break the app.

## Wiring it in (per product)

```dart
// 1. The product's configuration — one instance, usually a top-level final.
final netCruxTelemetryConfig = CruxTelemetryConfig(
  productSlug: 'netcrux',
  userAgentName: 'NetCrux',
);

// 2. A persistence adapter over the preferences layer you already own.
class NetCruxTelemetryStorage extends TelemetryStorage {
  const NetCruxTelemetryStorage();

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

// 3. The root ProviderScope overrides.
ProviderScope(
  overrides: [
    cruxTelemetryConfigProvider.overrideWithValue(netCruxTelemetryConfig),
    telemetryStorageProvider.overrideWithValue(
      const NetCruxTelemetryStorage(),
    ),
    telemetryUrlLauncherProvider.overrideWithValue(launchUrl),
    telemetryAppVersionProvider.overrideWith(
      (ref) async => (await ref.watch(applicationBuildInfoProvider.future))
          .version,
    ),
    telemetryFormFactorProvider.overrideWith(
      (ref) => telemetryFormFactorForNetCrux(ref.watch(deviceClassProvider)),
    ),
    telemetryLocaleProvider.overrideWith(
      (ref) => ref.watch(appSettingsProvider).value?.locale ?? 'en',
    ),
  ],
  child: const NetCruxApp(),
);

// 4. Mount the gate inside MaterialApp (so your strings adapter resolves)
// and inside any beta-expiry gate.
TelemetryConsentGate(
  isPhoneLayout: deviceClass.isPhoneClass,
  metrics: CruxTelemetryConsentMetrics(
    touchTarget: metrics.touchTarget,
    iconSize: metrics.iconSize,
    bodyFontSize: metrics.bodyText,
  ),
  child: routedContent,
);

// 5. Offer Settings → Privacy only where the pipeline can transmit.
if (ref.watch(telemetryConsentUiVisibleProvider))
  const TelemetrySettingsSection(),

// 6. Record events. Unconditionally.
ref.read(telemetryServiceProvider).record(
  TelemetryEvent('file.opened', properties: {'format': 'vcd'}),
);
```

## The Enterprise policy seam

An Enterprise deployment puts the telemetry decision for a seat with the
IT admin, in the signed `.crux-policy.json` key
`telemetry: allow | deny`: when it is present the first-launch dialog is
suppressed and the policy decides, and individual engineers see no
telemetry prompt.

**This package does not read that file.** `crux_policy` reads, verifies
and resolves it, and exposes the `telemetry` key through `DayOnePolicy`;
the Pro overlay binds that answer to `telemetryPolicyProvider` with one
override. What ships here is telemetry's half of the contract:
`TelemetryPolicy`, the `telemetryPolicyProvider` seam, and the gate
behaviour, complete and tested.

The precedence, highest first:

| # | Condition | Effect |
|---|---|---|
| 1 | Beta (`kBetaPeriod`) and no `TELEMETRY_DEV` | **Nothing collects**, and no consent surface mounts — including under `policy: allow`. |
| 2 | `TelemetryPolicy.deny` | Never collects. No consent surface mounts. Beats a stored `enabled`. |
| 2 | `TelemetryPolicy.allow` | Collects. No consent surface mounts. Beats a stored `disabled`. |
| 3 | `TelemetryPolicy.absent` (default) | Consent decides — `enabled` collects, `disabled` and `unset` do not, `unset` counts as consent under the dev flag alone. Both surfaces are offered. |

Two of those orderings are the load-bearing ones.

**The org beats the individual.** On an Enterprise seat the machine and
the licence belong to the organisation, and the decision sits with the
admin precisely so it is uniform across a fleet rather than
per-engineer. A personal `enabled` surviving a `deny` would leak from a
fleet the admin believes is silent; a personal `disabled` surviving an
`allow` would make the fleet's numbers quietly incomplete. Neither is the
seat's call — which is also why the Settings → Privacy toggle disappears
along with the dialog. A toggle the gate ignores tells the user they have
a choice and then discards it.

**The beta beats the org.** The App Store privacy label and the Play Data
safety form ship in the same release that flips `kBetaPeriod`, and
an IT administrator has no standing to authorise undeclared collection on
the stores' behalf. `allow` means "collect once collection begins", never
"begin".

**A policy never writes the consent store.** It is a runtime decision,
not a recorded user choice. Remove the key — or take the machine out of
the fleet — and the installation falls back to whatever the engineer had
actually chosen, which for almost all of them is `unset`, and therefore a
prompt. Persisting the mandate would silently convert an org decision
into a personal consent that outlives it.

## The uncaught-error counter

Every product installs `FlutterError.onError` and
`PlatformDispatcher.onError` before `runApp`, through
`crux_issue_reporter`'s `captureFlutterErrors`. Those handlers fill an
in-memory ring and write to stderr — and a Finder-launched macOS app sends
stderr to `/dev/null`, and a Windows GUI app has none. So a crash in a
GUI-launched release build used to leave no durable trace at all.
`captureFlutterErrors` now also reports each error to
`TelemetryUncaughtErrorCounter.instance`, which records it as one event:

```json
{ "name": "app.uncaught_error",
  "properties": { "source": "flutter", "kind": "state_error",
                  "library": "widgets", "silent": false } }
```

- **The shape of the error, never its content.** `source` is which handler
  saw it (`flutter` or `platform`; no product runs a guarded zone).
  `kind` is the error's class bucketed by `is` checks into
  `kTelemetryUncaughtErrorKinds` — never `runtimeType.toString()`, which an
  obfuscated release build scrambles and which is open-ended in any build.
  `library` is `FlutterErrorDetails.library` mapped onto the names the
  framework itself emits, `none` for a `platform` error, `other` for anything
  else. `silent` is `FlutterErrorDetails.silent`. No message, no stack, no
  file name, no `toString` of anything.
- **Once per `(source, kind, library)` per session, ten tuples at most.** A
  fault and its cascade fit inside ten; past that the rows describe the same
  broken session again and let one installation outweigh many in the totals.
- **The same gate as every other event.** `telemetryServiceProvider`
  attaches the counter to whichever service it resolves — live, pending or
  no-op — so there is no second consent check to drift. Errors from before
  the container existed wait in a buffer bounded by the session cap, and are
  handed to that service when it attaches: queued if consent is on, held and
  then replayed or dropped if it is still loading, discarded if it is off.
- **Inert during the beta**, by the same condition that closes the gate, so
  a beta build holds nothing in memory.
- **An editor host that overrides `telemetryServiceProvider` attaches
  nothing**; its relay never sees the event.

A test reads the resolved Flutter SDK and fails if the framework reports a
library name `kTelemetryFlutterLibraryTokens` does not map, so a toolchain
upgrade cannot quietly start filing a real library under `other`. A new
token means updating each product's catalog entry and the ingestion
Worker's schema for this event, which enforces the vocabulary exactly and
drops a value it does not know. `test/fixtures/uncaught-error-vocabulary.json`
is this package's copy of the Worker's vocabulary contract, and a test holds
the constants to it — so change the Worker first, then the copy, then the
constants.

## Payload contract

`test/fixtures/valid-batch.json` carries the same data as the ingestion
Worker's canonical batch document, whose acceptance the Worker's own suite
asserts. `telemetry_payload_contract_test.dart`
asserts this package's serializer emits that same document, key order
included. Hold both and the client and the Worker cannot have drifted —
which matters because the Worker's envelope validation is all-or-nothing:
one wrong field costs the user's whole queue.

```json
{
  "installation_id": "6f1b0d3e-…",
  "app_version": "0.6.0",
  "product": "wavecrux",
  "os": "macos",
  "form_factor": "desktop",
  "locale": "zh_CN",
  "license_tier": "openCore",
  "session_start": "2026-08-04T09:15:00Z",
  "events": [
    { "name": "decoder.opened", "properties": { "decoder": "spi" }, "count": 4 }
  ]
}
```

## Behavior contract

- **Nothing escapes `LiveTelemetryService`.** Every public entry point is
  wrapped; every I/O and network path swallows. A telemetry failure that
  breaks a decoder is strictly worse than losing the counter.
- **Nothing is sent inline with the event that produced it.** `start()`
  posts the queue the *previous* session left behind; this session's
  events go out on the next six-hourly tick or the next launch. No user
  action ever waits on the network, and coalescing has something to
  coalesce.
- **Where the queue has no file behind it, the cadence is 60 s, not 6 h.**
  Web, and anywhere else `path_provider` cannot give the queue a
  directory. That contract above rests entirely on there *being* a next
  launch; with a memory-only queue there is not one, so "the next launch
  ships it" means "nothing ever ships" — which is exactly what four
  products' web builds did. In that mode `record()` arms one flush per
  `volatileFlushInterval` window (per window, not per event, so a busy
  session still makes progress), and the host's hidden/paused/detached
  signal flushes too, because it is the only warning a browser tab gives.
  **Desktop and mobile are untouched**: there the file *is* the handover,
  and a near-term cadence would buy nothing but POSTs.
- **A flush the envelope *deferred* retries in a minute, on every host.**
  Not a cadence — the same flush, finished late, carrying the events it
  was already carrying. Otherwise "defer and retry on the next tick"
  means six hours, and a launch flush that loses a first-frame race just
  hands the queue to a next launch that races the same frame again.
- **A 4xx that is not a 429 drops the batch.** It is malformed for this
  endpoint and will be malformed forever; retrying it is exactly the
  traffic the caps exist to prevent. A 429 or a 5xx is "later" — keep the
  rows and back off, doubling to a six-hour ceiling.
- **A row that cannot fit on its own is dropped**, so it cannot wedge the
  queue behind it.
- **The queue is capped at 2000 events and 7 days**, dropping the oldest.
  An installation that never reaches the network does not grow a file on
  the user's disk.
- **`unset` is not consent.** It is the state that means "the disclosure
  has not been answered yet", and it is the only signal that tells the UI to
  show it. Quitting with the disclosure on screen writes nothing, so the next
  launch shows it again; only Continue (or the Settings toggle) stops it
  returning. Under the `TELEMETRY_DEV` flag alone it counts as enabled, so
  end-to-end staging verification needs no UI — but only **once the store
  has settled**. Before that, `unset` is the placeholder a stored refusal
  also wears, and promoting it would transmit from the very installation
  that said no.
- **The disclosure *and* the dev-flag promotion wait on the store's
  `loaded` signal, not on its state.** The store publishes `unset`
  synchronously. A gate keyed on the state alone would re-ask a user who
  answered on a previous launch — and, under the dev flag, collect from
  one who declined.
- **"Not yet" is a third answer, and it buffers.** Waiting for the store
  creates a window, and the window is not incidental: the store's read
  does not *start* until something reads the telemetry graph, so the
  first event of every launch falls inside it by construction. Resolving
  the no-op there does not defer that event, it deletes it — and on web,
  where a passive session may record nothing else, that is the session.
  So `telemetryGateProvider` has a `pending` value,
  `PendingTelemetryService` holds those events in memory, and when the
  gate resolves they are replayed into the live service or dropped with
  the buffer. Buffering is not collecting; nothing leaves the machine
  from that state. **The beta never enters it** — the dark-launch branch
  answers `closed` synchronously, so a beta build holds no telemetry in
  memory any more than it sends any.
- **`form_factor` may be `null` and that is not a failure.** A product
  that derives it from the layout idiom it drew cannot answer before the
  first frame, and the launch flush runs ahead of the widget tree. The
  envelope defers exactly as it does for an unresolved `app_version`,
  because a wrong `form_factor` is *accepted* by the Worker and silently
  books a tablet as a desktop, where a wrong `app_version` at least fails
  loudly. A derivation that cannot race — a host predicate, `kIsWeb` —
  must keep returning a value.
- **The disclosure is pre-armed on, and nothing else weighs the scale.**
  The switch sits directly above Continue, both lists are on screen
  before the user can act, and every control clears 44 dp on every host —
  "off" is never harder to reach than "on".
- **`form_factor` is derived by the product**, from the layout idiom it
  already drew. A second breakpoint set here is how telemetry comes to
  disagree with what the user is looking at.

## What is never collected

No file names, paths or contents. No design data of any kind — no signal
names, netlists, sources or results. No IP addresses, hostnames or MAC
addresses (the Worker stamps `country` from Cloudflare request metadata,
so the client never handles a location). No name, email or account
identity. No session duration — nothing records when a session ends, so
it is not merely unsent, it is never computed. No per-event timestamps.

`installation_id` is a random v4 UUID from `Random.secure()`, never
derived from anything the machine knows about itself. The point is not
that a fingerprint would be unreadable; it is that a fingerprint would be
stable across reinstalls and correlatable with other data, and a random
UUID is neither.

`telemetryEnumToken` takes an `Enum` rather than a `String` for the same
reason: a `String → String` sanitizer would accept a file name and wash
it into a token that passes the Worker's character class, which the
Worker cannot catch because the output *is* well formed.

## Localization

Like every `crux_shared` package, this one contains **no ARB files**.
`CruxTelemetryStrings` is the seam; each product maps it onto its own
generated localizations and owns the five-locale (en/zh_CN/zh/ja/ko)
parity sweep. The package's own widget tests sweep string *sets*,
directionality and text scale instead of locales.

## Status

Stable as of 0.1.0. `crux_telemetry` deliberately does **not** contain:

- **Any event catalog.** Each product pins its own, with a conformance
  test that scans its source for recorded names and checks every name,
  key and value against the Worker's grammar. That test cannot live here
  — it is the one thing that is genuinely per-product. (`app.uncaught_error`
  is recorded here, but it is listed in each product's catalog all the same.)
- **The `form_factor` derivation.** A provider seam; see above.
- **Any Enterprise policy-file parsing.** Reading, locating and
  signature-checking `.crux-policy.json` is an overlay concern that lands
  with the `crux_license` validator; from here it is one override of
  `telemetryPolicyProvider`. The behaviour that override selects *is*
  implemented and tested here — see "The Enterprise policy seam".
- **An opt-out data-deletion path.** There is no per-installation
  deletion endpoint, because there is nothing keyed to a person to
  delete.

## Visibility & license

Private during the public beta. Apache 2.0 at the post-beta open-core
flip, alongside every product's open-core repo. **Both** implementations
of `TelemetryService` ship in open core deliberately: the honesty
backstop for collecting from free users is that the entire pipeline is
readable — and strippable — in the Apache-2.0 source, which it cannot be
if half of it lives in a closed overlay.
