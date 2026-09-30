// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/src/crux_update_config.dart';
import 'package:crux_updates/src/crux_update_strings.dart';
import 'package:crux_updates/src/models/update_edition.dart';
import 'package:crux_updates/src/models/update_policy.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Signature of the "open this URL" seam the update banner drives.
///
/// Matches `url_launcher`'s `launchUrl`, which is what every product binds it
/// to. Kept as a seam so this package takes no plugin dependency and widget
/// tests can exercise the banner actions without a platform channel.
typedef CruxUpdateUrlLauncher = Future<bool> Function(Uri uri);

/// Signature of the observed-server-time sink.
///
/// Called with the manifest's `server_time` on every successful fetch.
typedef ObservedServerTimeSink = void Function(DateTime serverTime);

/// The consuming product's update configuration.
///
/// **Has no default binding.** A product that forgets to override it gets an
/// [UnimplementedError] the first time anything in the update graph is read —
/// at app wiring, not silently at runtime three weeks after a release. Retry is
/// disabled so the failure stays a single, legible error rather than a loop.
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     cruxUpdateConfigProvider.overrideWithValue(netCruxUpdateConfig),
///   ],
///   child: const MyApp(),
/// );
/// ```
final Provider<CruxUpdateConfig> cruxUpdateConfigProvider =
    Provider<CruxUpdateConfig>(
      (_) => throw UnimplementedError(
        'cruxUpdateConfigProvider has no default binding. Override it in the '
        'root ProviderScope with your product CruxUpdateConfig (manifest URI, '
        'product name, download page).',
      ),
      name: 'cruxUpdateConfigProvider',
      retry: (_, _) => null,
    );

/// Localized strings for the update banner and the manual-check action.
///
/// Defaults to [CruxUpdateStringsEn] named after
/// [CruxUpdateConfig.productName], so an un-localized build or a test renders
/// sensible English. Each product overrides this with an adapter over its own
/// generated `AppLocalizations`.
final Provider<CruxUpdateStrings> cruxUpdateStringsProvider =
    Provider<CruxUpdateStrings>(
      (ref) => CruxUpdateStringsEn(
        productName: ref.watch(cruxUpdateConfigProvider).productName,
      ),
      name: 'cruxUpdateStringsProvider',
    );

/// Build metadata for the running application, or `null` while it is still
/// loading (or when the product has not wired it).
///
/// The update check needs the running version to compare against the manifest
/// and the OS label for the `User-Agent`. Products override this with their own
/// `applicationBuildInfoProvider`:
///
/// ```dart
/// updateBuildInfoProvider.overrideWith(
///   (ref) => ref.watch(applicationBuildInfoProvider.future),
/// ),
/// ```
///
/// The `null` default is deliberately *safe* rather than loud: until build info
/// resolves, `updateCheckServiceProvider` yields a `NoopUpdateCheckService`, so
/// a check that races startup reports "current" rather than comparing against
/// an unknown version.
final FutureProvider<ApplicationBuildInfo?> updateBuildInfoProvider =
    FutureProvider<ApplicationBuildInfo?>(
      (_) async => null,
      name: 'updateBuildInfoProvider',
    );

/// Whether the *automatic* (launch + periodic + on-resume) check may run.
///
/// The injectable seam for each product's "automatically check for updates"
/// setting. It is a [FutureProvider] because the setting is persisted: the
/// notifier awaits it so a user who disabled auto-check is honored even on the
/// very first launch tick, before defaults would say "on".
///
/// ```dart
/// autoUpdateCheckEnabledProvider.overrideWith(
///   (ref) async => (await ref.watch(appSettingsProvider.future))
///       .autoCheckForUpdates,
/// ),
/// ```
///
/// Defaults to `true` (auto-check on), matching the suite-wide setting default.
/// The manual `checkNow` path ignores this entirely.
final FutureProvider<bool> autoUpdateCheckEnabledProvider =
    FutureProvider<bool>(
      (_) async => true,
      name: 'autoUpdateCheckEnabledProvider',
    );

/// Sink for the authoritative `server_time` observed on every successful
/// manifest fetch.
///
/// Defaults to a no-op. Products that carry a beta expiry override it with a
/// persisted, monotonic store whose value they feed back into `crux_license`'s
/// `observedServerTimeProvider` — that pairing is what makes the beta-expiry
/// clock resistant to a device-clock rollback.
///
/// ```dart
/// observedServerTimeSinkProvider.overrideWith(
///   (ref) => ref.read(observedServerTimeStoreProvider.notifier).record,
/// ),
/// ```
final Provider<ObservedServerTimeSink> observedServerTimeSinkProvider =
    Provider<ObservedServerTimeSink>(
      (_) => _ignoreServerTime,
      name: 'observedServerTimeSinkProvider',
    );

void _ignoreServerTime(DateTime _) {}

/// Opens the changelog / download / store URL the banner points at.
///
/// **Has no working default**: invoking the unbound launcher throws, because
/// silently doing nothing when the user taps "Update Now" is the worse failure.
/// Every product binds this to `url_launcher`:
///
/// ```dart
/// updateUrlLauncherProvider.overrideWithValue(launchUrl),
/// ```
final Provider<CruxUpdateUrlLauncher> updateUrlLauncherProvider =
    Provider<CruxUpdateUrlLauncher>(
      (_) => _unwiredLauncher,
      name: 'updateUrlLauncherProvider',
    );

Future<bool> _unwiredLauncher(Uri uri) {
  throw UnimplementedError(
    'updateUrlLauncherProvider has no default binding. Override it with '
    "url_launcher's launchUrl (or an equivalent) so the update banner can "
    'open $uri.',
  );
}

/// The organization's update constraints, if a policy file governs this
/// installation.
///
/// Defaults to [UpdatePolicy.absent] — no policy file — which is the state of
/// every non-Enterprise installation and of any Enterprise one whose
/// administrator set none of the three keys. On that default the update graph
/// behaves in every respect as it did before this seam existed.
///
/// The loader exists: `crux_policy` reads, verifies and resolves
/// `.crux-policy.json`, and `DayOnePolicy` exposes `updateChannel`,
/// `pinnedVersion` and `manifestUrl`. Binding it is one override in the Pro
/// overlay, and [UpdatePolicy.fromNames] documents it.
///
/// This package still never reads the file, and must not: it does not know the
/// format, where it lives, or how its signature is validated. Same seam shape,
/// and for the same reasons, as `telemetryPolicyProvider` in `crux_telemetry`.
///
/// **Read strictly after the managed-install verdict.** See
/// `updateCheckServiceProvider`, and `ManagedInstall` for why that ordering is
/// not a detail.
final Provider<UpdatePolicy> updatePolicyProvider = Provider<UpdatePolicy>(
  (_) => UpdatePolicy.absent,
  name: 'updatePolicyProvider',
);

/// Whether this seat has paid features unlocked, which decides whether a
/// release that changed only paid features is offered to it.
///
/// Defaults to [UpdateEdition.unlocked] — every newer release offered, exactly
/// as before this seam existed. Each product binds it from the same gate its
/// paid features use; [UpdateEdition.of] documents the override.
///
/// **Watched for changes, not only read at check time.** A key entered
/// mid-session, or a licence that lapses, changes the answer while the last
/// check's result is still on screen. `updateStatusProvider` re-presents that
/// result under the new edition at once and without a second manifest fetch,
/// so a user who has just bought a licence sees the release their build was
/// being withheld without waiting for the next scheduled check.
///
/// This package still does not know what a licence tier is and must not: no
/// shared package outside `crux_license` may branch on a paid tier. The
/// product maps its tier to this answer.
final Provider<UpdateEdition> updateEditionProvider = Provider<UpdateEdition>(
  (_) => UpdateEdition.unlocked,
  name: 'updateEditionProvider',
);

/// Whether the running build is a browser build.
///
/// `kIsWeb`, behind a provider purely as the test seam: a VM test cannot flip
/// the constant, and `updateCheckServiceProvider`'s web branch has to be
/// assertable from one. Nothing in the suite overrides it outside tests.
final Provider<bool> updateHostIsWebProvider = Provider<bool>(
  (_) => kIsWeb,
  name: 'updateHostIsWebProvider',
);

/// The HTTP client used for update-manifest fetches.
///
/// Exists as a provider purely as the test seam: the update-check regression
/// tests override it with a `MockClient` so the full provider graph — service
/// construction, fetch, server-time recording — runs hermetically.
final Provider<http.Client> updateHttpClientProvider = Provider<http.Client>(
  (ref) {
    final client = http.Client();
    ref.onDispose(client.close);
    return client;
  },
  name: 'updateHttpClientProvider',
);
