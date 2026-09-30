// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show Completer, unawaited;

import 'package:crux_telemetry/src/models/telemetry_consent_state.dart';
import 'package:crux_telemetry/src/providers/telemetry_seam_providers.dart';
import 'package:crux_telemetry/src/storage/telemetry_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persisted, per-installation record of the user's telemetry decision.
///
/// **Deliberately not a settings field.** A product's settings document is the
/// user's preference file — the thing they copy to a second machine or hand to
/// a colleague. Consent is a property of *this installation*: it pairs with the
/// installation id, it is what the first-launch disclosure writes, and
/// the storage key is fixed by the suite spec at exactly
/// [kTelemetryConsentKey]. That is the same reason
/// `update.observedServerTime` lives outside `settings.*`, and this store is
/// modelled on it.
///
/// [build] returns [TelemetryConsentState.unset] **synchronously** and kicks
/// off the load. Consumers therefore see "not answered yet" for the first few
/// frames of a cold start, and in that window a stored refusal and a genuine
/// first launch are the same value. **Every consumer for which that difference
/// matters must wait on [loaded] rather than read the state** — the
/// first-launch dialog does, and so does `telemetryGateProvider`'s dev-flag
/// promotion of `unset`, which is the one path where `unset` means "collect".
class TelemetryConsentStore extends Notifier<TelemetryConsentState> {
  /// The storage key holding the consent state, fixed by the suite spec.
  ///
  /// Re-exported here so a call site holding the store does not also have to
  /// import the storage library for the one constant.
  static const String storageKey = kTelemetryConsentKey;

  final Completer<void> _loaded = Completer<void>();

  /// Completes once the persisted value has been read back — whatever the
  /// outcome, including "nothing was stored".
  ///
  /// [build] deliberately publishes [TelemetryConsentState.unset] before the
  /// read lands, so in those first frames a returning installation that already
  /// answered and a fresh one are indistinguishable by state alone. Two
  /// consumers therefore wait on this rather than on the state:
  ///
  ///  * the **disclosure dialog**, because mounting on that value would re-ask
  ///    a user who has already decided — the one behaviour the "never asked
  ///    again once answered" promise rules out; and
  ///  * `telemetryGateProvider`, **under the dev flag only**, where `unset`
  ///    is promoted to consent so staging verification needs no UI. With the
  ///    flag off, `unset` reads as "do not collect" either way and the early
  ///    value is genuinely harmless. With it on, honouring the early value is
  ///    the difference between respecting a stored `disabled` and transmitting
  ///    from the installation that stored it.
  ///
  /// The pattern generalises: the state answers "what did they choose", this
  /// answers "have they been asked", and any consumer that needs the second
  /// question cannot substitute the first.
  Future<void> get loaded => _loaded.future;

  @override
  TelemetryConsentState build() {
    unawaited(_load());
    return TelemetryConsentState.unset;
  }

  Future<void> _load() async {
    try {
      final storage = ref.read(telemetryStorageProvider);
      final stored = TelemetryConsentState.tryParse(
        await storage.read(storageKey),
      );
      // The store outlives most things, but a container teardown mid-read
      // still disposes it — never touch `state` across the gap without this.
      if (!ref.mounted) return;
      if (stored != null) state = stored;
    } on Object catch (_) {
      // A storage layer that throws is a storage layer we do not have; the
      // state stays `unset`, which collects nothing.
    } finally {
      // Signalled even when the read threw or the container went away: a
      // disclosure that waits forever on an unreadable store is a first launch
      // with no disclosure at all, and the un-answered state it would be left
      // in collects nothing.
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  /// Records the user's decision and persists it.
  ///
  /// The in-memory state is set before the first async gap so a caller that
  /// immediately re-reads the provider sees the new value. The persist itself
  /// is deliberately **not** guarded by `ref.mounted`: once the user has
  /// answered, losing the answer because the container happened to tear down
  /// would re-prompt them on the next launch, which is the one behaviour the
  /// "never asked again once answered" promise rules out.
  Future<void> set(TelemetryConsentState consent) async {
    final storage = ref.read(telemetryStorageProvider);
    if (ref.mounted) state = consent;
    await storage.write(storageKey, consent.name);
  }
}

/// The persisted telemetry consent decision.
///
/// Hand-written rather than generated: no package in `crux-shared` runs
/// `build_runner`, so the codegen the original in-product implementation
/// relied on was dropped rather than introduced into the workspace.
final NotifierProvider<TelemetryConsentStore, TelemetryConsentState>
telemetryConsentStoreProvider =
    NotifierProvider<TelemetryConsentStore, TelemetryConsentState>(
      TelemetryConsentStore.new,
      name: 'telemetryConsentStoreProvider',
    );
