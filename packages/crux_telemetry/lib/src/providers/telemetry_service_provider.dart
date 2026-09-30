// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_license/crux_license.dart' show licenseTierProvider;
import 'package:crux_telemetry/src/models/telemetry_consent_state.dart';
import 'package:crux_telemetry/src/models/telemetry_envelope.dart';
import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:crux_telemetry/src/models/telemetry_policy.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_store.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_ui_providers.dart';
import 'package:crux_telemetry/src/providers/telemetry_installation_id.dart';
import 'package:crux_telemetry/src/providers/telemetry_seam_providers.dart';
import 'package:crux_telemetry/src/services/live_telemetry_service.dart';
import 'package:crux_telemetry/src/services/noop_telemetry_service.dart';
import 'package:crux_telemetry/src/services/pending_telemetry_service.dart';
import 'package:crux_telemetry/src/services/telemetry_uncaught_error_counter.dart';
import 'package:crux_telemetry/src/telemetry_platform.dart';
import 'package:crux_telemetry/src/telemetry_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the gate is [TelemetryGate.open]: a yes/no view of
/// [telemetryGateProvider], for tests and diagnostics.
///
/// **This is not the gate, and nothing in the pipeline watches it.**
/// [telemetryServiceProvider] watches [telemetryGateProvider], and that is the
/// answer that decides whether anything is collected or transmitted. This
/// cannot disagree with it — it is the gate compared to `open` — but it folds
/// [TelemetryGate.pending] into `false`, which is right for "may it transmit
/// now" and wrong for "will an event recorded now be kept". Ask
/// [telemetryGateProvider] for the second, and read it for the precedence.
final Provider<bool> telemetryEnabledProvider = Provider<bool>(
  (ref) => ref.watch(telemetryGateProvider) == TelemetryGate.open,
  name: 'telemetryEnabledProvider',
);

/// What the gate can say, including the answer it could not say before.
///
/// Transmission is decided by [open] alone. The distinction between [closed]
/// and [pending] is **not** about transmission — neither transmits — it is
/// about what happens to an event recorded right now, and that difference is
/// worth a type because getting it wrong silently loses every launch counter.
/// See [PendingTelemetryService].
enum TelemetryGate {
  /// Collect and transmit.
  open,

  /// Do not collect, and the answer will not change on its own: the beta gate,
  /// an Enterprise `deny`, or a stored `disabled`. Events are discarded.
  closed,

  /// The consent decision is not knowable yet — the store has published its
  /// `unset` placeholder and has not finished reading the persisted value back.
  /// Nothing transmits, and events are **buffered** rather than discarded,
  /// because the answer is minutes of milliseconds away and the events in
  /// question are the ones the launch produced.
  pending,
}

/// The telemetry gate: whether the live pipeline may transmit, as a
/// tri-state. [telemetryServiceProvider] chooses which service to resolve —
/// live, no-op or pending — from this alone.
///
/// Three independent conditions, in this order — and the order is the whole
/// design:
///
///  1. **The dark-launch gate.** During the beta, and without the dev flag,
///     this is `closed` no matter what else is true — including an explicit
///     `enabled` consent and including an Enterprise `TelemetryPolicy.allow`.
///     The suite promises no telemetry during beta, and a promise that can be
///     overridden by a stored preference is not the promise that was made. The
///     same holds against a policy file, and more sharply: the store privacy
///     declarations ship in the flip release, so a build that
///     transmitted before it would be shipping undeclared collection —
///     something an administrator has no standing to authorise on Apple's and
///     Google's behalf. A policy file can decide *whether* we collect once
///     collection exists; it cannot bring the date forward.
///  2. **The Enterprise policy.** [TelemetryPolicy.deny] never transmits and
///     [TelemetryPolicy.allow] always does, both of them beating whatever is in
///     the consent store. That inversion of the usual "the user decides" rule
///     is deliberate: on an Enterprise seat the machine belongs to the
///     organisation, the licence is the organisation's, and the decision
///     sits with the IT admin precisely so it is uniform across the fleet
///     rather than per-engineer. An individual `enabled` that survived a `deny`
///     would leak from a fleet the admin believes is silent; an individual
///     `disabled` that survived an `allow` would make the fleet's numbers
///     quietly incomplete. Neither is the individual's call to make, which is
///     also why no consent surface mounts under either value
///     (`telemetryConsentUiVisibleProvider`).
///
///     Note what this deliberately does **not** do: it never writes the consent
///     store. The policy is a runtime decision, not a recorded user choice, so
///     an installation that leaves the org — or an admin who removes the key —
///     falls back to whatever the engineer had actually chosen, which for most
///     of them is `unset` and therefore a prompt. Persisting the mandate would
///     convert it into a personal consent that outlives it.
///  3. **Consent.** With no policy ([TelemetryPolicy.absent], the default and
///     the state of every non-Enterprise installation): `enabled` transmits.
///     `disabled` does not. `unset` does not either — except under the dev
///     flag, where it counts as `enabled` so end-to-end verification against
///     the staging dataset needs no UI, and then **only once the consent store
///     has settled**.
///
///     That last clause is load-bearing rather than pedantic.
///     [TelemetryConsentStore] publishes `unset` synchronously and reads the
///     persisted value asynchronously, so for the first frames of a cold start
///     a stored *refusal* and "never answered" are the same value. With `dev`
///     off that is harmless in both directions — during the beta the branch
///     above has already returned, and post-flip the test is
///     `consent == enabled`, which `unset` fails safe. Under the dev flag it is
///     not harmless: it is the whole difference between honouring a stored
///     `disabled` and transmitting from the installation that set it. So the
///     promotion waits on [telemetryConsentReadyProvider] — the same `loaded`
///     signal the disclosure already waits on, and for the same reason: before
///     it completes, the state is not yet an answer. Until then the gate says
///     [TelemetryGate.pending].
final Provider<TelemetryGate> telemetryGateProvider = Provider<TelemetryGate>(
  (ref) {
    final dev = ref.watch(telemetryDevModeProvider);
    // The dark launch is not a "not yet" — during the beta there is nothing to
    // settle and nothing to buffer, and a beta build must hold no telemetry in
    // memory any more than it may send any.
    if (!dev && ref.watch(telemetryBetaPeriodProvider)) {
      return TelemetryGate.closed;
    }

    switch (ref.watch(telemetryEffectivePolicyProvider)) {
      case TelemetryPolicy.deny:
        // Unambiguous in every region: do not collect and do not prompt.
        return TelemetryGate.closed;
      case TelemetryPolicy.allow:
        // The org decided; nothing waits on the individual's store. Note this
        // reads the EFFECTIVE policy, which has already downgraded `allow` to
        // `absent` in the regions where an organization's config file cannot
        // supply the user's consent.
        return TelemetryGate.open;
      case TelemetryPolicy.absent:
        break;
    }

    final consent = ref.watch(telemetryConsentStoreProvider);
    final settled = ref.watch(telemetryConsentReadyProvider).hasValue;
    if (settled) {
      return consent == TelemetryConsentState.enabled ||
              (dev && consent == TelemetryConsentState.unset)
          ? TelemetryGate.open
          : TelemetryGate.closed;
    }
    // Not settled. `enabled` in this window is the store's placeholder, not the
    // user — the only value it can be showing is `unset`, whichever way the
    // installation actually answered — so this is `pending` and not `open`.
    return TelemetryGate.pending;
  },
  name: 'telemetryGateProvider',
);

/// Events recorded while the gate was [TelemetryGate.pending].
///
/// Container-scoped rather than held by [PendingTelemetryService], because the
/// service is replaced the instant the gate resolves and the events have to
/// survive that replacement to be worth buffering. Emptied either way: replayed
/// into the live service when the gate opens, dropped when it closes.
final Provider<List<TelemetryEvent>> telemetryPendingBufferProvider =
    Provider<List<TelemetryEvent>>(
      (_) => <TelemetryEvent>[],
      name: 'telemetryPendingBufferProvider',
    );

/// The uncaught-error counter [telemetryServiceProvider] attaches to whichever
/// service it resolves.
///
/// [TelemetryUncaughtErrorCounter.instance] — the counter the global error
/// handlers report to — unless a test overrides it with its own instance. A
/// seam rather than a direct reference because that instance is process-wide,
/// and a test that attached it to a throwaway container would be attaching the
/// real one.
final Provider<TelemetryUncaughtErrorCounter>
telemetryUncaughtErrorCounterProvider = Provider<TelemetryUncaughtErrorCounter>(
  (_) => TelemetryUncaughtErrorCounter.instance,
  name: 'telemetryUncaughtErrorCounterProvider',
);

/// Collects the batch envelope for the next flush, or `null` if it cannot be
/// collected yet.
///
/// Called per flush rather than once at construction, so a long-running session
/// reports the license tier and form factor it currently has rather than the
/// ones it booted with. Reads (never watches) so a window resize does not tear
/// down and rebuild the service — and with it the queue.
///
/// Returns `null` on any failure, and on either of the two fields that have a
/// real "not yet" state on a cold start:
///
///  * an **app version** that has not resolved. Inventing one would fail the
///    Worker's version check and cost the whole batch.
///  * a **form factor** the product cannot answer yet — see
///    [telemetryFormFactorProvider]. A product deriving it from the layout
///    idiom it drew cannot know it before the first frame, and the launch flush
///    runs before that: this function is called from a service, ahead of the
///    widget tree that would supply it. Fabricating the pre-layout default is
///    worse than sending nothing, because a wrong `form_factor` is not visibly
///    wrong — it silently books mobile installations as desktop, and
///    `form_factor` is one of the two fields the store privacy declarations
///    exist to answer. Skipping
///    costs one flush interval; the events stay queued.
///
/// The two are handled identically on purpose. "Defer, return null, retry next
/// tick" is the pipeline's one answer to a field that is not knowable yet, and
/// a second answer for the second field is how the two drift apart.
Future<TelemetryEnvelope?> resolveTelemetryEnvelope(Ref ref) async {
  try {
    final config = ref.read(cruxTelemetryConfigProvider);

    final installationId = await ref.read(
      telemetryInstallationIdProvider.future,
    );
    if (!ref.mounted) return null;

    final appVersion = await ref.read(telemetryAppVersionProvider.future);
    if (!ref.mounted || appVersion == null) return null;

    final formFactor = ref.read(telemetryFormFactorProvider);
    if (formFactor == null) return null;

    return TelemetryEnvelope(
      installationId: installationId,
      appVersion: appVersion,
      product: config.productSlug,
      // Derived here, not taken from any product's build info: a build info
      // `os` is a display string like `macOS 15.0`, which fails the Worker's
      // enum check on every platform.
      os: telemetryOsSlug(),
      formFactor: formFactor,
      locale: ref.read(telemetryLocaleProvider),
      licenseTier: ref.read(licenseTierProvider).name,
      sessionStart: ref.read(telemetrySessionStartProvider),
      userAgentName: config.userAgentName,
    );
  } on Object catch (_) {
    return null;
  }
}

/// The envelope resolver handed to [LiveTelemetryService].
///
/// A seam over [resolveTelemetryEnvelope] so a product with an envelope
/// requirement this package does not model can replace the whole assembly
/// rather than fork the service. Nothing in the suite overrides it today.
final Provider<TelemetryEnvelopeResolver> telemetryEnvelopeResolverProvider =
    Provider<TelemetryEnvelopeResolver>(
      (ref) =>
          () => resolveTelemetryEnvelope(ref),
      name: 'telemetryEnvelopeResolverProvider',
    );

/// Whether the gate is closed only because the consent question is still
/// open: the store has settled on [TelemetryConsentState.unset] and this build
/// offers the disclosure that will answer it.
///
/// Every other closed gate is a real no — the beta, an Enterprise `deny`, a
/// stored `disabled` — and none of those changes on its own. This one does,
/// the moment the user answers, which is why [telemetryServiceProvider] treats
/// it as a longer pending window rather than as a refusal. It reads through the
/// same providers the gate does, so a build that would never show the
/// disclosure can never hold events waiting for an answer that cannot come.
bool _awaitingConsentAnswer(Ref ref) =>
    ref.watch(telemetryConsentUiVisibleProvider) &&
    ref.watch(telemetryConsentReadyProvider).hasValue &&
    ref.watch(telemetryConsentStoreProvider) == TelemetryConsentState.unset;

/// Re-reads [telemetryServiceProvider] the moment the gate opens, so the
/// live service is built — and the launch's buffer replayed and flushed — by
/// something other than the next recorded event.
///
/// A stale provider with no listener is never recomputed. The service provider
/// watches the gate, so a gate that opens invalidates it, but nothing rebuilds
/// it until something reads it, and the instrumentation call sites only read
/// it to record. On a passive web session that is never: the launch counter
/// was the one event, and it is sitting in the buffer waiting for a service
/// that will not exist until the tab is closed.
///
/// One subscription per container, armed the first time the service provider
/// resolves and held here rather than by the service provider itself, because
/// a subscription registered on the service provider's own `ref` is torn down
/// by `onDispose` at the moment its dependencies change — which is exactly the
/// moment it would have fired. This provider depends on nothing, so it is never
/// invalidated and its subscription outlives every rebuild of the one it reads.
///
/// Whichever way a closed gate opens — the disclosure's yes, the Settings
/// toggle, an Enterprise policy that lands at runtime — the effect is the same
/// read the pending branch already performs when the store settles.
final Provider<void> _gateOpenedWatcherProvider = Provider<void>(
  (ref) {
    final container = ref.container;
    final subscription = container.listen<TelemetryGate>(
      telemetryGateProvider,
      (previous, next) {
        if (next == TelemetryGate.open && previous != TelemetryGate.open) {
          container.read(telemetryServiceProvider);
        }
      },
    );
    ref.onDispose(subscription.close);
  },
  name: 'telemetryGateOpenedWatcherProvider',
);

/// The active [TelemetryService] — the single point at which the suite's
/// anonymous usage statistics are switched on or off.
///
/// Resolves [LiveTelemetryService] only when [telemetryGateProvider] is
/// [TelemetryGate.open], [NoopTelemetryService] when it is
/// [TelemetryGate.closed] for good, and [PendingTelemetryService] for the two
/// windows where the answer is not knowable yet: while the consent store is
/// still reading, and — once it has read back `unset` — while the disclosure
/// is on screen waiting to be answered. Every implementation ships in
/// open-core: the honesty backstop for collecting from free users is that the
/// entire pipeline is readable — and strippable — in the Apache-2.0 source,
/// which it cannot be if half of it lives in a closed overlay.
///
/// The pending branch is the one that is easy to talk yourself out of. It
/// transmits nothing, exactly as the no-op does, so it looks like a
/// complication in aid of nothing — until you notice that the consent store's
/// read does not *start* until something reads this provider, which means the
/// first event of every launch is recorded inside the window by construction.
/// Resolving the no-op there does not defer that event, it deletes it. See
/// [PendingTelemetryService].
///
/// **This provider is the dark launch.** The live service, the queue and the
/// ingest URL are all present in every beta build and all of it is inert,
/// because during the beta [telemetryGateProvider] is [TelemetryGate.closed]
/// regardless of consent and nothing here ever constructs the live service.
/// Activation is the `kBetaPeriod` flip, not a merge.
///
/// Instrumentation call sites stay tier-agnostic and consent-agnostic: they
/// record unconditionally, and an opted-out or beta build hits the
/// allocation-free no-op.
///
/// **Every service this resolves is attached to the uncaught-error counter**
/// ([telemetryUncaughtErrorCounterProvider]), so `app.uncaught_error` reaches
/// the same gate as every other event with no wiring in any product. Attaching
/// the no-op is how a closed gate discards what the counter buffered before the
/// container existed; attaching the pending service is how those events wait
/// for the consent store like the launch counter does. A product that
/// overrides this provider — an editor host relaying events to its own sender
/// — attaches nothing, and the counter's buffer stays at its cap.
final Provider<TelemetryService> telemetryServiceProvider =
    Provider<TelemetryService>(
      (ref) {
        final buffer = ref.read(telemetryPendingBufferProvider);
        final gate = ref.watch(telemetryGateProvider);
        final errorCounter = ref.read(telemetryUncaughtErrorCounterProvider);

        TelemetryService attachErrorCounter(TelemetryService service) {
          errorCounter.attach(service);
          ref.onDispose(() => errorCounter.detach(service));
          return service;
        }

        final config = ref.watch(cruxTelemetryConfigProvider);

        if (gate == TelemetryGate.closed) {
          if (_awaitingConsentAnswer(ref)) {
            // Closed because nobody has answered yet — the store settled on
            // `unset`, and the disclosure is on screen asking. That is not a
            // no. Discarding the buffer here is what made every first session
            // silent: `workspace.restored` is recorded before the consent
            // store has even started reading, the settle lands on `unset`,
            // and the one event a passive web tab ever produces is gone
            // before the user has said yes. So the launch's events keep
            // waiting, exactly as they did while the store was still reading,
            // and whatever the session records while the prompt is up waits
            // with them under the same cap.
            //
            // And as in the pending branch, something has to READ this
            // provider once the answer arrives, or a stale provider with no
            // listener is never recomputed and the live service is never
            // built. A `yes` from the disclosure writes the store, which
            // flips the gate, which invalidates this provider — and then
            // nothing happens until the next event, which on a passive web
            // session is never. [_gateOpenedWatcherProvider] is that read.
            ref.read(_gateOpenedWatcherProvider);
            return attachErrorCounter(
              PendingTelemetryService(
                buffer,
                maxEvents: config.maxQueuedEvents,
              ),
            );
          }
          // Whatever the pending window collected was collected on the strength
          // of a placeholder, and the answer turned out to be no. It goes no
          // further than this line.
          buffer.clear();
          return attachErrorCounter(const NoopTelemetryService());
        }

        if (gate == TelemetryGate.pending) {
          // Resolve this provider again the moment the store settles, from the
          // container rather than from `ref` — a self-read here would be a
          // dependency cycle, and `ref.invalidateSelf` only marks it stale.
          //
          // Necessary because a stale provider with no listener is never
          // recomputed. Watching `telemetryGateProvider` invalidates this one
          // when the gate flips, but something has to *read* it for the live
          // service to be built and the buffer replayed — and on a passive web
          // session nothing ever will: the launch counter is the first read of
          // the telemetry graph and, with no user interaction, the last. It
          // would sit in the buffer until the tab closed.
          final container = ref.container;
          unawaited(
            ref
                .read(telemetryConsentReadyProvider.future)
                .then((_) {
                  container.read(telemetryServiceProvider);
                })
                .catchError((Object _) {
                  // A container torn down between the two. Nothing to resolve
                  // into, and nothing here may throw into a feature flow.
                }),
          );
          return attachErrorCounter(
            PendingTelemetryService(buffer, maxEvents: config.maxQueuedEvents),
          );
        }

        final service = LiveTelemetryService(
          endpoint: ref.watch(telemetryEndpointProvider),
          envelopeResolver: ref.watch(telemetryEnvelopeResolverProvider),
          client: ref.watch(telemetryHttpClientProvider),
          flushInterval: config.flushInterval,
          volatileFlushInterval: config.volatileFlushInterval,
          initialRetryDelay: config.initialRetryDelay,
          maxRetryDelay: config.maxRetryDelay,
          postTimeout: config.postTimeout,
          maxQueuedEvents: config.maxQueuedEvents,
          maxEventAge: config.maxEventAge,
        );
        // Registered before `start()` so a container torn down mid-launch-flush
        // still cancels the timers.
        ref.onDispose(service.dispose);
        // Replayed before `start()` so these events are already on the queue —
        // and on disk — when the launch flush runs, rather than a tick behind
        // it. They are the launch's own counters: recorded while the consent
        // store was still reading, by an installation that has now been
        // confirmed to permit collection.
        if (buffer.isNotEmpty) {
          buffer
            ..forEach(service.record)
            ..clear();
        }
        attachErrorCounter(service);
        service.start();
        return service;
      },
      name: 'telemetryServiceProvider',
    );
