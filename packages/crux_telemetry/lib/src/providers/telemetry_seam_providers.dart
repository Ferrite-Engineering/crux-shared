// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:crux_license/crux_license.dart' show kBetaPeriod;
import 'package:crux_telemetry/src/crux_telemetry_config.dart';
import 'package:crux_telemetry/src/crux_telemetry_strings.dart';
import 'package:crux_telemetry/src/models/telemetry_policy.dart';
import 'package:crux_telemetry/src/storage/telemetry_storage.dart';
import 'package:crux_telemetry/src/telemetry_endpoint.dart';
import 'package:crux_telemetry/src/telemetry_region.dart';
import 'package:crux_telemetry/src/telemetry_time_zone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Signature of the "open this URL" seam the consent surfaces drive.
///
/// Matches `url_launcher`'s `launchUrl`, and matches `crux_updates`'
/// `CruxUpdateUrlLauncher` so a product that already bound one can bind this to
/// the same function. Kept as a seam so this package takes no plugin
/// dependency and the consent widget tests can exercise the documentation link
/// without a platform channel.
typedef CruxTelemetryUrlLauncher = Future<bool> Function(Uri uri);

/// The consuming product's telemetry configuration.
///
/// **Has no default binding.** A product that forgets to override it gets an
/// [UnimplementedError] the first time anything in the telemetry graph is
/// read — at app wiring, not silently at runtime with somebody else's product
/// slug on every batch. Retry is disabled so the failure stays a single,
/// legible error rather than a loop.
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     cruxTelemetryConfigProvider.overrideWithValue(netCruxTelemetryConfig),
///   ],
///   child: const MyApp(),
/// );
/// ```
final Provider<CruxTelemetryConfig> cruxTelemetryConfigProvider =
    Provider<CruxTelemetryConfig>(
      (_) => throw UnimplementedError(
        'cruxTelemetryConfigProvider has no default binding. Override it in '
        'the root ProviderScope with your product CruxTelemetryConfig '
        '(product slug, User-Agent name).',
      ),
      name: 'cruxTelemetryConfigProvider',
      retry: (_, _) => null,
    );

/// Localized strings for the consent disclosure and the Settings → Privacy
/// section.
///
/// Defaults to [CruxTelemetryStringsEn] named after
/// [CruxTelemetryConfig.userAgentName], so an un-localized build or a test
/// renders sensible English. Each product overrides this with an adapter over
/// its own generated `AppLocalizations` — and, because that needs a
/// `BuildContext`, does it from inside `MaterialApp.builder` rather than in the
/// root scope.
final Provider<CruxTelemetryStrings> cruxTelemetryStringsProvider =
    Provider<CruxTelemetryStrings>(
      (ref) => CruxTelemetryStringsEn(
        productName: ref.watch(cruxTelemetryConfigProvider).userAgentName,
      ),
      name: 'cruxTelemetryStringsProvider',
    );

/// Where the consent decision and the installation id are persisted.
///
/// Defaults to a process-lifetime [InMemoryTelemetryStorage]. That default is
/// **safe but visibly wrong** in production — the disclosure re-prompts every
/// launch — which is the loudest failure available to a subsystem whose whole
/// contract is that it never throws into a feature flow. Products bind a small
/// adapter over the preferences layer they already own:
///
/// ```dart
/// telemetryStorageProvider.overrideWithValue(
///   const SharedPreferencesTelemetryStorage(),
/// ),
/// ```
final Provider<TelemetryStorage> telemetryStorageProvider =
    Provider<TelemetryStorage>(
      (_) => InMemoryTelemetryStorage(),
      name: 'telemetryStorageProvider',
    );

/// The HTTP client used for telemetry ingest POSTs.
///
/// A provider purely as the test seam, mirroring `updateHttpClientProvider`:
/// the gating tests override it with a `MockClient` so the whole graph —
/// service resolution, flush, backoff — runs hermetically, and so the
/// beta-inert test can assert on the *absence* of requests rather than on the
/// absence of a class.
final Provider<http.Client> telemetryHttpClientProvider = Provider<http.Client>(
  (ref) {
    final client = http.Client();
    ref.onDispose(client.close);
    return client;
  },
  name: 'telemetryHttpClientProvider',
);

/// Opens the suite telemetry disclosure page from either consent surface.
///
/// **Has no working default**: invoking the unbound launcher throws, because
/// silently doing nothing when the user taps "Learn more" on a privacy
/// disclosure is the worse failure. Every product binds this to `url_launcher`:
///
/// ```dart
/// telemetryUrlLauncherProvider.overrideWithValue(launchUrl),
/// ```
final Provider<CruxTelemetryUrlLauncher> telemetryUrlLauncherProvider =
    Provider<CruxTelemetryUrlLauncher>(
      (_) => _unwiredLauncher,
      name: 'telemetryUrlLauncherProvider',
    );

Future<bool> _unwiredLauncher(Uri uri) {
  throw UnimplementedError(
    'telemetryUrlLauncherProvider has no default binding. Override it with '
    "url_launcher's launchUrl (or an equivalent) so the consent surfaces can "
    'open $uri.',
  );
}

/// Riverpod-overridable view of [kTelemetryDev].
///
/// The compile-time constant stays the production source of truth; this exists
/// so the gating matrix can be exercised without one build per cell.
final Provider<bool> telemetryDevModeProvider = Provider<bool>(
  (_) => kTelemetryDev,
  name: 'telemetryDevModeProvider',
);

/// Whether the public beta is still running, **for telemetry purposes only**.
///
/// This deliberately reads the `crux_license` constant [kBetaPeriod] rather
/// than `betaPeriodProvider`, even though a provider exists and the house style
/// is to prefer it. Products override `betaPeriodProvider` to `false` on mobile
/// hosts — a **badging** decision (a store build must not advertise a public
/// beta, App Store Review Guideline 2.2), not a statement that the beta has
/// ended. Reading it here would flip the dark-launch switch on iOS and Android
/// while desktop stayed inert, which is precisely the accident the dark launch
/// exists to prevent: the store privacy declarations ship in the flip release,
/// so a mobile build that transmitted early would be shipping undeclared
/// collection.
///
/// Telemetry therefore keys off the real beta state and gets its own override
/// seam for tests.
final Provider<bool> telemetryBetaPeriodProvider = Provider<bool>(
  (_) => kBetaPeriod,
  name: 'telemetryBetaPeriodProvider',
);

/// The Enterprise administrator's org-wide telemetry decision, if one governs
/// this installation.
///
/// Defaults to [TelemetryPolicy.absent] — no policy file — which is the state
/// of every non-Enterprise installation and of any Enterprise one whose admin
/// did not set the key. On that default the gate and both consent surfaces
/// behave exactly as they did before this seam existed.
///
/// **The loader now exists**: `crux_policy` reads, verifies and resolves
/// `.crux-policy.json`, and `DayOnePolicy` exposes the `telemetry` key as one
/// of the three that resolve *before a licence exists*. Binding it is one
/// override in the Pro overlay:
///
/// ```dart
/// telemetryPolicyProvider.overrideWith((ref) {
///   final policy = ref.watch(dayOnePolicyProvider);
///   return switch (policy.telemetry) {
///     PolicyTelemetryDecision.deny => TelemetryPolicy.deny,
///     PolicyTelemetryDecision.allow => TelemetryPolicy.allow,
///     PolicyTelemetryDecision.absent => TelemetryPolicy.absent,
///   };
/// }),
/// ```
///
/// This package still never reads the file, and must not: it does not know the
/// format, where it lives, or how its signature is validated. It knows only the
/// shape of the answer and the behaviour that answer selects.
///
/// A plain [Provider] rather than anything asynchronous, for the same reason
/// `telemetryConsentPromptVisibleProvider` is: the overlay is expected to
/// resolve the policy once during wiring and expose it synchronously, and a
/// gate that could be "still loading" would have to pick a behaviour for that
/// window — which is a third policy state nobody asked for.
final Provider<TelemetryPolicy> telemetryPolicyProvider =
    Provider<TelemetryPolicy>(
      (_) => TelemetryPolicy.absent,
      name: 'telemetryPolicyProvider',
    );

/// [telemetryPolicyProvider] after the ePrivacy region rule is applied.
///
/// **Read this, not the raw policy**, anywhere the answer decides whether
/// telemetry flows or whether a consent surface is offered. The gate and the
/// consent UI both do, and they must agree: if `allow` closed the consent
/// surface but did not open the gate, a user in a consent-required region could
/// never consent — telemetry would stay off with no way to turn it on, and the
/// organization would believe it was on.
///
/// The rule:
///
/// - `deny` → `deny`, everywhere. Unambiguous in every region.
/// - `allow` → `allow` where the region permits an opt-out default;
///   **`absent` in the EEA, the UK, Switzerland and South Korea** — the same
///   set `telemetry_region.dart` defines — because the installation id is
///   storage on the user's device that needs consent there (ePrivacy
///   Art. 5(3) and its UK and Swiss equivalents; PIPA's consent-first regime
///   in Korea), consent is the only lawful basis, and *an organization's
///   configuration file is not the user's consent*.
/// - `absent` → `absent`.
///
/// Whether an employer's own lawful basis can carry `allow` in those regions
/// is a legal question rather than a technical one. Until it is
/// answered this is the conservative half — and `deny`, which is what an
/// Enterprise deployment actually asks for, needs no answer at all.
final Provider<TelemetryPolicy> telemetryEffectivePolicyProvider =
    Provider<TelemetryPolicy>((ref) {
      final policy = ref.watch(telemetryPolicyProvider);
      if (policy != TelemetryPolicy.allow) return policy;
      return ref.watch(telemetryDefaultConsentProvider)
          ? TelemetryPolicy.allow
          : TelemetryPolicy.absent;
    }, name: 'telemetryEffectivePolicyProvider');

/// The ingest URL this build posts to.
final Provider<Uri> telemetryEndpointProvider = Provider<Uri>(
  (ref) => ref
      .watch(cruxTelemetryConfigProvider)
      .endpointFor(dev: ref.watch(telemetryDevModeProvider)),
  name: 'telemetryEndpointProvider',
);

/// The running build's version string, or `null` while it is still loading (or
/// when the product has not wired it).
///
/// `null` is a **real** state on a cold start, and it is why the envelope is
/// nullable all the way down: inventing an `app_version` to fill the gap would
/// fail the Worker's version check and cost the whole batch, so a flush that
/// races startup skips instead. Products override this from their own build
/// info:
///
/// ```dart
/// telemetryAppVersionProvider.overrideWith(
///   (ref) async => (await ref.watch(applicationBuildInfoProvider.future))
///       .version,
/// ),
/// ```
final FutureProvider<String?> telemetryAppVersionProvider =
    FutureProvider<String?>(
      (_) async => null,
      name: 'telemetryAppVersionProvider',
    );

/// The `form_factor` bucket reported in the envelope, or `null` while it is not
/// yet knowable.
///
/// Each product derives this from the layout idiom it **already** uses, so
/// telemetry can never disagree with what the user is actually looking at: if
/// the app drew phone chrome, the event says `phone`. The derivation is not
/// here because a second breakpoint set in this package is exactly the way the
/// two come to disagree.
///
/// ```dart
/// telemetryFormFactorProvider.overrideWith(
///   (ref) => telemetryFormFactorFor(
///     isWeb: kIsWeb,
///     deviceClass: ref.watch(resolvedDeviceClassProvider), // nullable
///   ),
/// ),
/// ```
///
/// **`null` is a real state, and it means "ask again next tick"** —
/// `resolveTelemetryEnvelope` returns `null` for it and the flush skips,
/// exactly as it does for an unresolved [telemetryAppVersionProvider]. A
/// product whose idiom comes from the widget tree (a display size pushed from
/// `MaterialApp.builder`) cannot answer this before the first layout, and the
/// launch flush runs before it: telemetry reads this provider from a service
/// ahead of the tree, not from inside it. Reporting the pre-layout default
/// instead would silently attribute mobile installations to `desktop`, and
/// `form_factor` is one of the two fields the collection exists to answer.
///
/// A product whose derivation is **unconditional** — a host predicate, or
/// `kIsWeb` — must keep returning a value. There is no race to lose there, and
/// deferring would cost the batch for nothing.
///
/// A non-`null` value must be a member of `kTelemetryFormFactors`; the default
/// is the desktop bucket, which is what an un-wired desktop-only host would
/// report anyway, and is unconditional for the same reason.
final Provider<String?> telemetryFormFactorProvider = Provider<String?>(
  (_) => 'desktop',
  name: 'telemetryFormFactorProvider',
);

/// The resolved app locale reported as the `locale` envelope field.
///
/// A seam rather than a direct read of any product's settings, both because
/// this package has no settings model and because a product's service layer
/// generally may not reach up into its feature layer. The `en` default is what
/// an un-wired test or a pre-settings-load flush reports.
final Provider<String> telemetryLocaleProvider = Provider<String>(
  (_) => 'en',
  name: 'telemetryLocaleProvider',
);

/// The platform's preferred locales, as the region signal behind the
/// first-launch default.
///
/// A seam, and read from [PlatformDispatcher] rather than from the app's
/// resolved locale on purpose: the two answer different questions. The app
/// locale says which translation is on screen — a German engineer running the
/// English build reports `en` — while this says which regional settings the
/// machine is configured with, which is the thing ePrivacy turns on.
/// [telemetryLocaleProvider] is the former and is an envelope field; this is
/// the latter and is never transmitted.
///
/// Nothing here is collected or stored. The value is read once, at the moment
/// the disclosure needs a default, and discarded.
final Provider<List<Locale>> telemetryPlatformLocalesProvider =
    Provider<List<Locale>>(
      (_) => PlatformDispatcher.instance.locales,
      name: 'telemetryPlatformLocalesProvider',
    );

/// The platform's resolved IANA time zone, as the second region signal behind
/// the first-launch default.
///
/// `null` everywhere but the web, where it is the browser's resolved zone —
/// `Europe/Berlin`, `America/Denver`. It exists because the locale signal goes
/// quiet exactly there: browsers commonly report a bare language tag with no
/// country, and a zone almost always carries a place. Off the web the VM can
/// only name an abbreviation, which is ambiguous, so desktop and mobile builds
/// are placed by locale alone. See `telemetry_time_zone.dart`.
///
/// Like the locales, this is read once at the moment the disclosure needs a
/// default, never stored and never transmitted.
final Provider<String?> telemetryPlatformTimeZoneProvider = Provider<String?>(
  (_) => platformIanaTimeZone(),
  name: 'telemetryPlatformTimeZoneProvider',
);

/// The position the first-launch toggle arrives in on this installation.
///
/// `false` in the EEA, the UK, Switzerland and South Korea, where consent must
/// come first; `true` everywhere else, which is the suite's default-on
/// decision. See `telemetry_region.dart` for the ruling, the country set, the
/// time-zone set, and the honest limits of deriving a region from either.
///
/// A provider rather than a constant so an Enterprise overlay — or a product
/// that acquires a better region signal than these — can override one value
/// instead of reaching into the widget.
final Provider<bool> telemetryDefaultConsentProvider = Provider<bool>(
  (ref) => telemetryDefaultConsentFor(
    ref.watch(telemetryPlatformLocalesProvider),
    timeZone: ref.watch(telemetryPlatformTimeZoneProvider),
  ),
  name: 'telemetryDefaultConsentProvider',
);

/// When this app session started (the `session_start` envelope field).
///
/// Evaluated once, on first read, and kept for the life of the container —
/// which is the life of the app process. Nothing records when a session
/// *ends*: session duration is on the never-collect list, so the end is not
/// merely unsent, it is never computed.
final Provider<DateTime> telemetrySessionStartProvider = Provider<DateTime>(
  (_) => DateTime.now(),
  name: 'telemetrySessionStartProvider',
);
