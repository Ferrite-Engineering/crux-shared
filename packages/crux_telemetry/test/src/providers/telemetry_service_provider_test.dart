// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart'
    show
        LicenseTier,
        LicenseTierFeatures,
        betaPeriodProvider,
        kBetaPeriod,
        licenseTierProvider;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every request the container's telemetry graph made. The gate is asserted
  /// against *traffic*, not just against a class name: "no telemetry during
  /// beta" is a promise about what leaves the machine.
  late List<http.BaseRequest> requests;

  /// The storage the container's consent store reads and writes. Held so the
  /// policy tests can assert on what was *persisted*, not merely on what the
  /// in-memory state reports.
  late InMemoryTelemetryStorage storage;

  ProviderContainer containerFor({
    required bool beta,
    required bool dev,
    required TelemetryConsentState consent,
    TelemetryPolicy policy = TelemetryPolicy.absent,
  }) {
    requests = <http.BaseRequest>[];
    storage = InMemoryTelemetryStorage();
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(storage),
        telemetryBetaPeriodProvider.overrideWithValue(beta),
        telemetryDevModeProvider.overrideWithValue(dev),
        telemetryPolicyProvider.overrideWithValue(policy),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            requests.add(request);
            return http.Response('{"accepted":1,"dropped":0}', 202);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (consent != TelemetryConsentState.unset) {
      container.read(telemetryConsentStoreProvider.notifier).state = consent;
    }
    return container;
  }

  group('telemetryServiceProvider gating matrix', () {
    // policy × beta × dev × consent, complete — all 36 cells. This map is the
    // canonical statement of the gate; anything that changes the precedence
    // changes it here, in one place, where the whole rule is visible at once.
    //
    // Read the three policy blocks as the precedence order:
    //
    //   1. beta (without the dev flag) beats everything, INCLUDING a policy;
    //   2. an Enterprise policy beats the individual's stored consent;
    //   3. with no policy — every non-Enterprise installation — consent
    //      decides, exactly as it always has.
    //
    // The `unset` cells are here in every block rather than only where they
    // differ, because `unset` behaves differently under the dev flag and a
    // matrix with a hole in it is not a matrix.
    const expectations =
        <(TelemetryPolicy, bool beta, bool dev, TelemetryConsentState), bool>{
          // ══ No policy file. Every non-Enterprise installation, and the
          //    default. These twelve cells are the pre-policy behaviour and
          //    must stay untouched by everything below. ═════════════════════
          // ── Beta. Inert in every cell, consent notwithstanding. ──────────
          (TelemetryPolicy.absent, true, false, TelemetryConsentState.enabled):
              false,
          (TelemetryPolicy.absent, true, false, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.absent, true, false, TelemetryConsentState.unset):
              false,
          // ── Beta + the dev flag: the dark-launch verification path. ──────
          (TelemetryPolicy.absent, true, true, TelemetryConsentState.enabled):
              true,
          (TelemetryPolicy.absent, true, true, TelemetryConsentState.disabled):
              false,
          // `unset` counts as consent under the dev flag only, so end-to-end
          // verification against the staging dataset needs no UI.
          (TelemetryPolicy.absent, true, true, TelemetryConsentState.unset):
              true,
          // ── Post-beta: consent decides. ──────────────────────────────────
          (TelemetryPolicy.absent, false, false, TelemetryConsentState.enabled):
              true,
          (
            TelemetryPolicy.absent,
            false,
            false,
            TelemetryConsentState.disabled,
          ): false,
          (TelemetryPolicy.absent, false, false, TelemetryConsentState.unset):
              false,
          (TelemetryPolicy.absent, false, true, TelemetryConsentState.enabled):
              true,
          (TelemetryPolicy.absent, false, true, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.absent, false, true, TelemetryConsentState.unset):
              true,

          // ══ policy: deny. The org forbids collection. False in all twelve
          //    cells — there is no combination of beta, dev flag or stored
          //    consent that transmits from a machine whose administrator said
          //    no. Note especially the `enabled` cells: an engineer who ticked
          //    the box before the policy arrived does not get to keep
          //    transmitting, because the machine and the licence are the
          //    organisation's. ══════════════════════════════════════════════
          (TelemetryPolicy.deny, true, false, TelemetryConsentState.enabled):
              false,
          (TelemetryPolicy.deny, true, false, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.deny, true, false, TelemetryConsentState.unset):
              false,
          (TelemetryPolicy.deny, true, true, TelemetryConsentState.enabled):
              false,
          (TelemetryPolicy.deny, true, true, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.deny, true, true, TelemetryConsentState.unset):
              false,
          (TelemetryPolicy.deny, false, false, TelemetryConsentState.enabled):
              false,
          (TelemetryPolicy.deny, false, false, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.deny, false, false, TelemetryConsentState.unset):
              false,
          (TelemetryPolicy.deny, false, true, TelemetryConsentState.enabled):
              false,
          (TelemetryPolicy.deny, false, true, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.deny, false, true, TelemetryConsentState.unset):
              false,

          // ══ policy: allow. The org mandates collection — and it still loses
          //    to the beta gate. ════════════════════════════════════════════
          // ── Beta, no dev flag: inert, policy notwithstanding. The store
          //    privacy declarations ship in the flip release; an administrator
          //    cannot authorise undeclared collection on Apple's and Google's
          //    behalf, so a policy file can decide WHETHER we collect but not
          //    WHEN we start. ────────────────────────────────────────────────
          (TelemetryPolicy.allow, true, false, TelemetryConsentState.enabled):
              false,
          (TelemetryPolicy.allow, true, false, TelemetryConsentState.disabled):
              false,
          (TelemetryPolicy.allow, true, false, TelemetryConsentState.unset):
              false,
          // ── Beta + dev flag: the gate is open, and the policy decides —
          //    including over a stored `disabled`. ───────────────────────────
          (TelemetryPolicy.allow, true, true, TelemetryConsentState.enabled):
              true,
          (TelemetryPolicy.allow, true, true, TelemetryConsentState.disabled):
              true,
          (TelemetryPolicy.allow, true, true, TelemetryConsentState.unset):
              true,
          // ── Post-beta: collect, whatever the individual had chosen. ──────
          (TelemetryPolicy.allow, false, false, TelemetryConsentState.enabled):
              true,
          (TelemetryPolicy.allow, false, false, TelemetryConsentState.disabled):
              true,
          (TelemetryPolicy.allow, false, false, TelemetryConsentState.unset):
              true,
          (TelemetryPolicy.allow, false, true, TelemetryConsentState.enabled):
              true,
          (TelemetryPolicy.allow, false, true, TelemetryConsentState.disabled):
              true,
          (TelemetryPolicy.allow, false, true, TelemetryConsentState.unset):
              true,
        };

    test('the matrix is complete — every policy × beta × dev × consent', () {
      // A hole here would read as a passing suite. Three policies × two beta
      // states × two dev states × three consent states.
      expect(expectations, hasLength(3 * 2 * 2 * 3));
    });

    for (final entry in expectations.entries) {
      final (policy, beta, dev, consent) = entry.key;
      final live = entry.value;
      test(
        'policy=${policy.name} beta=$beta dev=$dev consent=${consent.name} → '
        '${live ? 'LiveTelemetryService' : 'NoopTelemetryService'}',
        () async {
          final container = containerFor(
            beta: beta,
            dev: dev,
            consent: consent,
            policy: policy,
          );

          // The matrix states the SETTLED behaviour, so let the store settle
          // before reading it. What happens in the window before it settles is
          // a different question with a different answer, and it has its own
          // group below — the one this matrix could not see, because seeding
          // through `notifier.state` never opens that window at all.
          await container.read(telemetryConsentReadyProvider.future);

          expect(
            container.read(telemetryServiceProvider),
            live ? isA<LiveTelemetryService>() : isA<NoopTelemetryService>(),
          );
        },
      );
    }
  });

  group('THE PRE-LOAD WINDOW — consent read back through storage', () {
    // The 36 cells above seed consent by assigning `notifier.state`, which is
    // synchronous and therefore never exercises the window between
    // `TelemetryConsentStore.build()` publishing `unset` and the persisted
    // value landing. Every one of them passed while a stored `disabled` was
    // transmitting under the dev flag on a real installation, because in that
    // window `disabled` and "never answered" are the same value, and the dev
    // flag promotes "never answered" to consent.
    //
    // These cells seed the STORAGE and assert before the read resolves. That is
    // the half of the fix that stops it coming back.

    /// Storage whose `read` hangs until the test releases it — the cold-start
    /// window, held open and made deterministic. A real `SharedPreferences`
    /// read closes it in a microtask or two, which is long enough on a device
    /// to have produced the defect and far too short to assert on.
    ({
      InMemoryTelemetryStorage storage,
      List<http.BaseRequest> requests,
      ProviderContainer container,
      void Function() release,
    })
    coldStart({
      required bool beta,
      required bool dev,
      TelemetryConsentState? stored,
      TelemetryPolicy policy = TelemetryPolicy.absent,
    }) {
      final gate = Completer<void>();
      final seeded = InMemoryTelemetryStorage(<String, String>{
        if (stored != null) kTelemetryConsentKey: stored.name,
      });
      final sent = <http.BaseRequest>[];
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
          telemetryStorageProvider.overrideWithValue(
            _GatedTelemetryStorage(seeded, gate.future),
          ),
          telemetryBetaPeriodProvider.overrideWithValue(beta),
          telemetryDevModeProvider.overrideWithValue(dev),
          telemetryPolicyProvider.overrideWithValue(policy),
          telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
          telemetryHttpClientProvider.overrideWithValue(
            MockClient((request) async {
              sent.add(request);
              return http.Response('{"accepted":1,"dropped":0}', 202);
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      return (
        storage: seeded,
        requests: sent,
        container: container,
        release: gate.complete,
      );
    }

    test(
      'a stored `disabled` does not transmit before the load lands',
      () async {
        // The leak, exactly: `flutter.telemetry.consent = disabled` on disk, a
        // TELEMETRY_DEV build, and a real row in the staging dataset from the
        // very installation that had refused.
        final cold = coldStart(
          beta: true,
          dev: true,
          stored: TelemetryConsentState.disabled,
        );

        expect(
          cold.container.read(telemetryEnabledProvider),
          isFalse,
          reason:
              'a refusal that has not finished loading is still a refusal — '
              'the gate may not read the placeholder as an open question',
        );
        final service = cold.container.read(telemetryServiceProvider);
        expect(service, isA<PendingTelemetryService>());

        // And assert it against traffic, not only against the class: the defect
        // was reported as a row in a dataset.
        for (var i = 0; i < 50; i++) {
          service.record(TelemetryEvent('workspace.restored'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(cold.requests, isEmpty);

        cold.release();
        await cold.container.read(telemetryConsentReadyProvider.future);

        expect(
          cold.container.read(telemetryEnabledProvider),
          isFalse,
          reason: 'and it stays a refusal once the value has actually landed',
        );
        expect(
          cold.container.read(telemetryServiceProvider),
          isA<NoopTelemetryService>(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(cold.requests, isEmpty);
        expect(
          cold.container.read(telemetryPendingBufferProvider),
          isEmpty,
          reason:
              'the buffer was collected on the strength of a placeholder; a '
              'refusal drops it rather than keeping it for later',
        );
      },
    );

    test(
      'a genuinely un-answered installation transmits — after the load',
      () async {
        // The other side of the same coin, and the reason the fix is "wait",
        // not "treat unset as disabled": under the dev flag `unset` really does
        // count as consent, so staging verification needs no UI. It just may
        // not count before anyone has looked.
        final cold = coldStart(beta: true, dev: true);

        expect(
          cold.container.read(telemetryEnabledProvider),
          isFalse,
          reason: 'nothing is known about this installation yet',
        );

        cold.release();
        await cold.container.read(telemetryConsentReadyProvider.future);

        expect(cold.container.read(telemetryEnabledProvider), isTrue);
        expect(
          cold.container.read(telemetryServiceProvider),
          isA<LiveTelemetryService>(),
        );
      },
    );

    test('the launch events recorded inside the window are not lost', () async {
      // The half of this that a "does it transmit?" assertion cannot see, and
      // the half that cost four products their web builds a second time.
      //
      // The consent store's read does not START until something reads the
      // telemetry graph, so the first event of a launch is inside this window
      // by construction — on all four products that is `workspace.restored`,
      // emitted from a notifier's `build`. Handing out the no-op there does not
      // defer that event, it deletes it, and on web a passive session records
      // nothing else at all.
      final cold = coldStart(beta: true, dev: true);

      final pending = cold.container.read(telemetryServiceProvider);
      expect(pending, isA<PendingTelemetryService>());
      pending.record(
        TelemetryEvent(
          'workspace.restored',
          properties: const <String, Object?>{'panes': 1, 'tabs': 0},
        ),
      );
      expect(cold.requests, isEmpty, reason: 'buffering is not collecting');

      cold.release();
      await cold.container.read(telemetryConsentReadyProvider.future);

      final live = cold.container.read(telemetryServiceProvider);
      expect(live, isA<LiveTelemetryService>());
      expect(
        (live as LiveTelemetryService).pending.map((e) => e.name),
        contains('workspace.restored'),
        reason:
            'the launch counter was recorded by an installation that has now '
            'been confirmed to permit collection; it belongs on the queue',
      );
      expect(
        cold.container.read(telemetryPendingBufferProvider),
        isEmpty,
        reason: 'replayed, not copied — a second resolution must not duplicate',
      );
    });

    test('the buffer ships with no second read of the provider', () async {
      // THE WEB SESSION, exactly. A passive browser session records one event —
      // the launch counter — and then nothing. So nothing reads
      // `telemetryServiceProvider` a second time, and if the transition out of
      // the pending state depends on someone doing that, the live service is
      // never constructed, the buffer never ships, and the tab closes silently.
      // Which is the same zero rows volatile mode exists to prevent, reached by
      // a third route.
      final cold = coldStart(beta: true, dev: true);

      cold.container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('workspace.restored'));

      cold.release();
      // Everything the container could do on its own, and nothing else: no
      // further read of the service, and no flush called by hand.
      for (var turn = 0; turn < 200 && cold.requests.isEmpty; turn++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(
        cold.requests,
        isNotEmpty,
        reason:
            'the launch counter must reach the endpoint on its own, from a '
            'session that never touches the telemetry graph again',
      );
      expect(
        (cold.requests.first as http.Request).body,
        contains('workspace.restored'),
      );
    });

    test('the buffer is capped, so a store that never answers cannot grow', () {
      final cold = coldStart(beta: true, dev: true);
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(
            CruxTelemetryConfig(
              productSlug: 'wavecrux',
              userAgentName: 'WaveCrux',
              maxQueuedEvents: 5,
            ),
          ),
          telemetryStorageProvider.overrideWithValue(
            _GatedTelemetryStorage(
              InMemoryTelemetryStorage(),
              Completer<void>().future,
            ),
          ),
          telemetryBetaPeriodProvider.overrideWithValue(true),
          telemetryDevModeProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(cold.container.dispose);

      final service = container.read(telemetryServiceProvider);
      for (var i = 0; i < 40; i++) {
        service.record(
          TelemetryEvent('tool.opened', properties: <String, Object?>{'i': i}),
        );
      }

      expect(container.read(telemetryPendingBufferProvider), hasLength(5));
      expect(
        container.read(telemetryPendingBufferProvider).last.properties['i'],
        39,
        reason: 'oldest dropped, exactly as the queue does at its own cap',
      );
    });

    test('a stored `enabled` waits for its own load too, post-beta', () async {
      // With the dev flag off the gate tests `consent == enabled`, so the
      // placeholder already fails safe and no wait was ever needed for
      // correctness here. Asserted anyway, because "fails safe" is a property
      // worth pinning: the direction of the pre-load answer is always "no".
      final cold = coldStart(
        beta: false,
        dev: false,
        stored: TelemetryConsentState.enabled,
      );

      expect(cold.container.read(telemetryEnabledProvider), isFalse);

      cold.release();
      await cold.container.read(telemetryConsentReadyProvider.future);

      expect(cold.container.read(telemetryEnabledProvider), isTrue);
      expect(
        cold.container.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });

    test('a storage layer that never answers never transmits', () async {
      // The completer is simply never released. A store that cannot be read is
      // not an installation that agreed; `_load`'s `finally` still completes
      // the signal on a throw, but a read that hangs forever has no throw to
      // catch, and the gate must stay shut on its own. It stays *pending*
      // rather than closed — the question is still open — and pending is
      // exactly as silent as closed, which is the property under test.
      final cold = coldStart(beta: true, dev: true);
      final service = cold.container.read(telemetryServiceProvider);

      for (var i = 0; i < 50; i++) {
        service.record(TelemetryEvent('workspace.restored'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service, isA<PendingTelemetryService>());
      expect(cold.container.read(telemetryEnabledProvider), isFalse);
      expect(cold.requests, isEmpty);
    });

    for (final policy in [TelemetryPolicy.allow, TelemetryPolicy.deny]) {
      test('an Enterprise ${policy.name} does not wait on the store', () async {
        // The policy branch returns before consent is consulted at all, so a
        // fleet under a policy is not held behind an installation's preference
        // read. `allow` is the cell that would regress if the wait were placed
        // one line too early.
        final cold = coldStart(
          beta: false,
          dev: false,
          stored: TelemetryConsentState.unset,
          policy: policy,
        );

        expect(
          cold.container.read(telemetryEnabledProvider),
          policy == TelemetryPolicy.allow,
        );
      });
    }
  });

  group('THE BETA-INERT TEST — the dark-launch guarantee', () {
    // LiveTelemetryService, the queue, and the ingest URL all ship in every
    // beta build, and every one of them is inert. Activation is the
    // kBetaPeriod flip, not a merge. If this test ever goes red, a beta build
    // is transmitting — before the store privacy declarations that must
    // accompany the first transmitting release have shipped.
    //
    // Swept over the Enterprise policy as well as over consent, because the
    // guarantee has to hold against `policy: allow` too. An administrator can
    // decide whether their fleet reports; they cannot move the date collection
    // begins, which is fixed by the App Store and Play declarations shipping in
    // the flip release.
    for (final policy in TelemetryPolicy.values) {
      for (final consent in TelemetryConsentState.values) {
        test(
          'during beta with no dev flag, policy=${policy.name} '
          'consent=${consent.name} sends nothing',
          () async {
            final container = containerFor(
              beta: true,
              dev: false,
              consent: consent,
              policy: policy,
            );

            final service = container.read(telemetryServiceProvider);
            expect(
              service,
              isA<NoopTelemetryService>(),
              reason:
                  'the live service must not even be constructed during beta',
            );

            // Record a launch catalog's worth of traffic and let every timer
            // and microtask the graph could have scheduled run.
            for (var i = 0; i < 50; i++) {
              service.record(
                TelemetryEvent(
                  'decoder.opened',
                  properties: const <String, Object?>{'decoder': 'spi'},
                ),
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));

            expect(
              requests,
              isEmpty,
              reason:
                  'ZERO HTTP calls may leave a beta build — the suite promises '
                  'no telemetry during the beta, and a promise that a stored '
                  'preference or an org policy file can override is not the '
                  'promise that was made',
            );
          },
        );
      }
    }

    test('an explicit `enabled` consent does not override the beta gate', () {
      final container = containerFor(
        beta: true,
        dev: false,
        consent: TelemetryConsentState.enabled,
      );
      expect(container.read(telemetryEnabledProvider), isFalse);
    });

    test('an Enterprise `allow` policy does not override the beta gate', () {
      // The org's decision beats the individual's. It does not beat the dark
      // launch: the App Store privacy label and the Play Data safety form ship
      // in the same release that flips `kBetaPeriod`, and an IT administrator
      // has no standing to authorise undeclared collection on the stores'
      // behalf. `allow` means "collect once collection begins", never "begin".
      final container = containerFor(
        beta: true,
        dev: false,
        consent: TelemetryConsentState.enabled,
        policy: TelemetryPolicy.allow,
      );
      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
    });

    test('the shipping build has ended the beta, so consent decides', () async {
      // The flip that activates telemetry is this constant, and nothing else:
      // a release passes no BETA_PERIOD define, so it ships the default.
      expect(kBetaPeriod, isFalse);
      expect(kTelemetryDev, isFalse);

      // Neither the beta nor the dev seam is overridden, so both read the
      // shipping defaults. The client and storage are, so nothing leaves the
      // test and no preference is read from the host.
      Future<ProviderContainer> shipping(TelemetryConsentState stored) async {
        final container = ProviderContainer(
          overrides: [
            cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
            telemetryStorageProvider.overrideWithValue(
              InMemoryTelemetryStorage(<String, String>{
                if (stored != TelemetryConsentState.unset)
                  kTelemetryConsentKey: stored.name,
              }),
            ),
            telemetryAppVersionProvider.overrideWith((_) async => '1.0.0'),
            telemetryHttpClientProvider.overrideWithValue(
              MockClient(
                (_) async => http.Response('{"accepted":1,"dropped":0}', 202),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(telemetryConsentReadyProvider.future);
        return container;
      }

      // Not answered is not consent: nothing is constructed that could send.
      final unanswered = await shipping(TelemetryConsentState.unset);
      expect(unanswered.read(telemetryBetaPeriodProvider), isFalse);
      expect(unanswered.read(telemetryEnabledProvider), isFalse);
      expect(
        unanswered.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );

      // A user who opted in is counted, with no define and no dev flag.
      final consented = await shipping(TelemetryConsentState.enabled);
      expect(consented.read(telemetryEnabledProvider), isTrue);
      expect(
        consented.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });

    test(
      "a host's mobile betaPeriodProvider override does NOT activate telemetry",
      () {
        // Products set betaPeriodProvider=false on mobile hosts so a store
        // build does not advertise a public beta (App Store Review Guideline
        // 2.2). That is a badging decision. If telemetry read that provider,
        // every iOS and Android beta build would start transmitting while
        // desktop stayed inert — and would do it before the store privacy
        // declarations shipped.
        //
        // So the beta is pinned on here rather than taken from the default:
        // the question is whether the badging override leaks into telemetry
        // while the beta is still running, and a build that has ended the
        // beta cannot ask it.
        final container = ProviderContainer(
          overrides: [
            cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
            telemetryStorageProvider.overrideWithValue(
              InMemoryTelemetryStorage(),
            ),
            telemetryBetaPeriodProvider.overrideWithValue(true),
            betaPeriodProvider.overrideWithValue(false),
            telemetryHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{}', 202)),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(telemetryConsentStoreProvider.notifier).state =
            TelemetryConsentState.enabled;

        expect(container.read(telemetryEnabledProvider), isFalse);
        expect(
          container.read(telemetryServiceProvider),
          isA<NoopTelemetryService>(),
        );
      },
    );
  });

  group('the Enterprise policy seam', () {
    // The matrix above states the whole gate; these assert the two consequences
    // that a `isA<…>` check cannot see — that `deny` produces no traffic, and
    // that neither policy value touches what the user actually chose.

    test('the default is absent — no policy governs an ordinary build', () {
      // Every non-Enterprise installation. If this ever defaults to anything
      // else, four products silently acquire an org mandate they never had.
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(telemetryPolicyProvider), TelemetryPolicy.absent);
    });

    test('deny beats a stored `enabled` — post-beta, zero HTTP', () async {
      final container = containerFor(
        beta: false,
        dev: false,
        consent: TelemetryConsentState.enabled,
        policy: TelemetryPolicy.deny,
      );

      final service = container.read(telemetryServiceProvider);
      expect(
        service,
        isA<NoopTelemetryService>(),
        reason:
            'an engineer who ticked the box before the policy arrived does not '
            'keep transmitting from a fleet the administrator believes silent',
      );

      for (var i = 0; i < 50; i++) {
        service.record(TelemetryEvent('decoder.opened'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requests, isEmpty);
    });

    test('allow beats a stored `disabled` — post-beta, live', () {
      // The mirror of the case above, and the reason `deny` is not simply
      // "off": both directions are the organisation's call, not the seat's.
      final container = containerFor(
        beta: false,
        dev: false,
        consent: TelemetryConsentState.disabled,
        policy: TelemetryPolicy.allow,
      );
      expect(container.read(telemetryEnabledProvider), isTrue);
      expect(
        container.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });

    for (final policy in [TelemetryPolicy.allow, TelemetryPolicy.deny]) {
      test('${policy.name} never writes the consent store', () async {
        // A policy is a RUNTIME decision, not a recorded user choice. If the
        // admin removes the key — or the machine leaves the fleet — the
        // installation must fall back to whatever the engineer had actually
        // chosen, which for almost all of them is `unset` and therefore a
        // prompt. Persisting the mandate would quietly convert it into a
        // personal consent that outlives the mandate, and the user would never
        // be asked.
        final container = containerFor(
          beta: false,
          dev: false,
          consent: TelemetryConsentState.unset,
          policy: policy,
        );

        // Resolve the whole graph — the service, the gate, and the store's
        // own load — so anything that would have written has had its chance.
        expect(
          container.read(telemetryServiceProvider),
          policy == TelemetryPolicy.allow
              ? isA<LiveTelemetryService>()
              : isA<NoopTelemetryService>(),
        );
        await container.read(telemetryConsentReadyProvider.future);

        expect(
          storage.values,
          isNot(contains(kTelemetryConsentKey)),
          reason: "nothing may have been persisted on the policy's behalf",
        );
        expect(
          container.read(telemetryConsentStoreProvider),
          TelemetryConsentState.unset,
          reason: 'the un-answered state survives the policy that overrode it',
        );
      });

      test('${policy.name} leaves an existing stored answer intact', () async {
        // The returning-installation case: this engineer answered on a
        // previous launch, and the policy landed afterwards. Their answer is
        // overridden for as long as the policy is in force, and no longer.
        final seeded = InMemoryTelemetryStorage(<String, String>{
          kTelemetryConsentKey: TelemetryConsentState.enabled.name,
        });
        final container = ProviderContainer(
          overrides: [
            cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
            telemetryStorageProvider.overrideWithValue(seeded),
            telemetryBetaPeriodProvider.overrideWithValue(false),
            telemetryDevModeProvider.overrideWithValue(false),
            telemetryPolicyProvider.overrideWithValue(policy),
            telemetryHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{}', 202)),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(telemetryServiceProvider);
        await container.read(telemetryConsentReadyProvider.future);

        expect(
          seeded.values[kTelemetryConsentKey],
          TelemetryConsentState.enabled.name,
        );
        expect(
          container.read(telemetryConsentStoreProvider),
          TelemetryConsentState.enabled,
        );
      });
    }
  });

  group('endpoint selection', () {
    test('the path selects the dataset', () {
      expect(
        telemetryEndpointFor(dev: false).toString(),
        'https://telemetry.edacrux.app/v1/events',
      );
      expect(
        telemetryEndpointFor(dev: true).toString(),
        'https://telemetry.edacrux.app/dev/v1/events',
      );
      // The config's own resolution must agree with the free function, or a
      // product could be pointed at production by a default it never set.
      expect(
        testTelemetryConfig.endpointFor(dev: false),
        telemetryEndpointFor(dev: false),
      );
      expect(
        testTelemetryConfig.endpointFor(dev: true),
        telemetryEndpointFor(dev: true),
      );
    });

    test(
      'the resolved live service posts to the staging path under dev',
      () async {
        final container = containerFor(
          beta: true,
          dev: true,
          consent: TelemetryConsentState.enabled,
        );
        await container.read(telemetryConsentReadyProvider.future);
        expect(
          container.read(telemetryEndpointProvider).toString(),
          'https://telemetry.edacrux.app/dev/v1/events',
        );
        expect(
          container.read(telemetryServiceProvider),
          isA<LiveTelemetryService>(),
        );
      },
    );
  });

  group('the envelope', () {
    test('reports the configured product slug and User-Agent name', () async {
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
          telemetryStorageProvider.overrideWithValue(
            InMemoryTelemetryStorage(),
          ),
          telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
          telemetryFormFactorProvider.overrideWithValue('tablet'),
          telemetryLocaleProvider.overrideWithValue('ja'),
        ],
      );
      addTearDown(container.dispose);

      final envelope = await container.read(
        telemetryEnvelopeResolverProvider,
      )();

      expect(envelope, isNotNull);
      expect(envelope!.product, testTelemetryConfig.productSlug);
      expect(envelope.userAgent, 'WaveCrux/0.6.0');
      expect(envelope.formFactor, 'tablet');
      expect(envelope.locale, 'ja');
      expect(kTelemetryOperatingSystems, contains(envelope.os));
      expect(kTelemetryLicenseTiers, contains(envelope.licenseTier));
    });

    test('reports every tier distinctly — EDU never becomes Pro', () async {
      // `LicenseTierFeatures.featureEquivalent` maps edu -> pro, because for
      // FEATURE GATING that is exactly right: an EDU seat unlocks the Pro
      // feature set. Reporting it here would be exactly wrong, and silently so.
      //
      // EDU is a discount programme with its own commercial question — is it
      // reaching students, and does it convert? Folding it into `pro` does not
      // produce a wrong-looking number that someone investigates; it produces
      // a plausible Pro count and an EDU population that appears not to exist.
      // The envelope therefore reports the RAW tier, and this test is what
      // stops a future simplification from reaching for `featureEquivalent`.
      for (final tier in LicenseTier.values) {
        final container = ProviderContainer(
          overrides: [
            cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
            telemetryStorageProvider.overrideWithValue(
              InMemoryTelemetryStorage(),
            ),
            telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
            licenseTierProvider.overrideWithValue(tier),
          ],
        );
        addTearDown(container.dispose);

        final envelope = await container.read(
          telemetryEnvelopeResolverProvider,
        )();

        expect(
          envelope!.licenseTier,
          tier.name,
          reason: 'every tier must be reportable as itself',
        );
      }

      // The two that the feature-gate equivalence would have merged.
      expect(LicenseTier.edu.featureEquivalent, LicenseTier.pro);
      expect(LicenseTier.edu.name, isNot(LicenseTier.pro.name));

      // And the Worker accepts all four, so none of them is dropped at ingest.
      expect(
        LicenseTier.values.map((t) => t.name),
        everyElement(isIn(kTelemetryLicenseTiers)),
      );
    });

    test('resolves to null while the app version is unknown', () async {
      // A cold start, or a product that has not wired the seam. Inventing an
      // app_version would fail the Worker's check and cost the whole batch.
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
          telemetryStorageProvider.overrideWithValue(
            InMemoryTelemetryStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(telemetryEnvelopeResolverProvider)(), isNull);
    });

    test('resolves to null while the form factor is unknowable', () async {
      // A product deriving `form_factor` from the layout idiom it drew
      // cannot answer before the first frame, and the launch flush runs before
      // it — the envelope is assembled from a service, ahead of the tree. The
      // pre-layout default is not a safe stand-in: unlike a bad app_version,
      // which the Worker rejects loudly, a wrong form_factor is accepted and
      // silently books a tablet as a desktop.
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
          telemetryStorageProvider.overrideWithValue(
            InMemoryTelemetryStorage(),
          ),
          telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
          telemetryFormFactorProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(telemetryEnvelopeResolverProvider)(), isNull);
    });

    test('the deferred form factor is picked up on the retry', () async {
      // The other half: deferring costs a flush interval, not the events. Once
      // the tree has reported a size the very next call resolves, and it
      // resolves to what the app actually drew.
      final formFactor = <String?>[null, 'tablet'].iterator;
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
          telemetryStorageProvider.overrideWithValue(
            InMemoryTelemetryStorage(),
          ),
          telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
          telemetryFormFactorProvider.overrideWith((_) {
            formFactor.moveNext();
            return formFactor.current;
          }),
        ],
      );
      addTearDown(container.dispose);

      final resolve = container.read(telemetryEnvelopeResolverProvider);
      expect(await resolve(), isNull);
      // A fresh read of the seam, exactly as the next flush would take.
      container.invalidate(telemetryFormFactorProvider);
      expect((await resolve())?.formFactor, 'tablet');
    });

    test('the package default is unconditional — an un-wired host reports', () {
      // Deferring is for products whose derivation races a first layout. The
      // package's own default is a constant, so it must never defer: a
      // desktop-only host that never wired the seam would otherwise report
      // nothing at all.
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(telemetryFormFactorProvider), 'desktop');
      expect(
        kTelemetryFormFactors,
        contains(container.read(telemetryFormFactorProvider)),
      );
    });
  });

  group('the seam itself', () {
    test('can be overridden with a recording fake', () {
      final recorder = _RecordingTelemetryService();
      final container = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(recorder)],
      );
      addTearDown(container.dispose);

      container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('debug_advisor.suggestion.accepted'));

      expect(recorder.events, hasLength(1));
      expect(recorder.events.first.name, 'debug_advisor.suggestion.accepted');
    });
  });

  group('the config seam', () {
    test('has no default binding — a product that forgets it fails loudly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Riverpod wraps a create-time throw, so assert on the cause: the
      // message has to name the override a product forgot.
      expect(
        () => container.read(cruxTelemetryConfigProvider),
        throwsA(
          isA<Object>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('UnimplementedError'),
              contains('cruxTelemetryConfigProvider has no default binding'),
            ),
          ),
        ),
      );
    });
  });
}

/// A [TelemetryStorage] whose reads complete only once its gate future does.
///
/// Holds the cold-start window — between `TelemetryConsentStore.build()`
/// publishing `unset` and the persisted value landing — open for as long as a
/// test needs to assert inside it. A real preferences read closes that window
/// in a microtask or two: long enough on a device to leak a stored refusal,
/// far too short to make an assertion against.
class _GatedTelemetryStorage extends TelemetryStorage {
  const _GatedTelemetryStorage(this._inner, this._gate);

  final TelemetryStorage _inner;
  final Future<void> _gate;

  @override
  Future<String?> read(String key) async {
    await _gate;
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> remove(String key) => _inner.remove(key);
}

class _RecordingTelemetryService implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}
