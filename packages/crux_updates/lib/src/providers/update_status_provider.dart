// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_updates/src/models/update_edition.dart';
import 'package:crux_updates/src/models/update_manifest.dart';
import 'package:crux_updates/src/models/update_status.dart';
import 'package:crux_updates/src/providers/update_check_service_provider.dart';
import 'package:crux_updates/src/providers/update_seam_providers.dart';
import 'package:crux_updates/src/update_check_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current [UpdateStatus] and drives update checks.
///
/// On creation it starts a periodic timer (`CruxUpdateConfig.checkInterval`,
/// 24 h by default) and fires one launch check; both the launch and periodic
/// checks are **gated** on [autoUpdateCheckEnabledProvider] (the product's
/// "automatically check for updates" setting). The manual [checkNow] entry
/// point ignores the setting — a manual check always runs.
///
/// A failed check resolves to [UpdateStatusError] (typed state), never a thrown
/// exception: the [UpdateCheckService] surfaces only the typed
/// [UpdateCheckException], and even an unexpected raw error is caught here so
/// nothing escapes.
///
/// ### The edition filter lives here, not in the service graph
///
/// Organization policy is applied by wrapping the service, because a policy
/// file is fixed for the life of the process. [updateEditionProvider] is not:
/// a user enters a licence key, or a licence lapses, while a check's result is
/// already on screen. So the service returns every newer release, this
/// notifier keeps the last one it was given, and [UpdateEdition.offers] is
/// applied each time a state is published — after a check, and again whenever
/// the edition changes. A licence change therefore re-presents the result it
/// already holds, instantly and without a second manifest fetch. Every
/// user-visible outcome, the manual check's included, reads this notifier's
/// state, so there is no path around the filter.
class UpdateStatusNotifier extends Notifier<UpdateStatus> {
  /// The newer release the last successful check returned, before the edition
  /// filter; `null` when that check found nothing newer.
  UpdateInfo? _offer;

  /// The running version that check compared against.
  String? _runningVersion;

  @override
  UpdateStatus build() {
    final interval = ref.watch(cruxUpdateConfigProvider).checkInterval;
    final timer = Timer.periodic(
      interval,
      (_) => unawaited(runScheduledCheck()),
    );
    ref.onDispose(timer.cancel);

    ref.listen<UpdateEdition>(updateEditionProvider, (previous, next) {
      if (previous != next) _republish();
    });

    // Launch check — same gated path the periodic timer uses.
    unawaited(runScheduledCheck());

    return const UpdateStatusCurrent();
  }

  /// Runs an auto-check **only if** the auto-check setting is enabled. This is
  /// the gated path shared by the launch check, every periodic-timer tick, and
  /// the `UpdateBanner`'s on-resume re-check.
  Future<void> runScheduledCheck() async {
    // Await the persisted setting so a user who disabled auto-check is honored
    // even on the very first launch tick (before defaults would say "on").
    final enabled = await ref.read(autoUpdateCheckEnabledProvider.future);
    // The launch check and the periodic timer both run through here, so this
    // future can still be in flight when the container tears down. Bail before
    // touching `state` — a post-dispose `state =` throws.
    if (!ref.mounted) return;
    if (!enabled) return;
    await _performCheck();
  }

  /// Runs a check immediately, regardless of the auto-check setting. Backs the
  /// manual "Check for Updates" action.
  Future<void> checkNow() => _performCheck();

  Future<void> _performCheck() async {
    state = const UpdateStatusChecking();
    try {
      // Ensure build info is loaded so the live service compares against the
      // real running version rather than the pre-load Noop fallback.
      final buildInfo = await ref.read(updateBuildInfoProvider.future);
      if (!ref.mounted) return;
      final service = ref.read(updateCheckServiceProvider);
      final info = await service.checkForUpdate();
      // Re-check before publishing the result so a disposed ref never sets
      // state.
      if (!ref.mounted) return;
      _offer = info;
      _runningVersion = buildInfo?.version;
      state = _present();
    } on UpdateCheckException {
      if (!ref.mounted) return;
      state = const UpdateStatusError();
    } on Object {
      // Defense in depth: the contract says only UpdateCheckException escapes
      // the service, but never let any raw error break a feature flow.
      if (!ref.mounted) return;
      state = const UpdateStatusError();
    }
  }

  /// The state the last successful check's result amounts to under the
  /// edition in force right now.
  UpdateStatus _present() {
    final offer = _offer;
    if (offer == null) return const UpdateStatusCurrent();
    final running = _runningVersion;
    // No running version means no comparison the edition rule could make, so
    // it offers, as the unfiltered check did.
    if (running != null &&
        !ref
            .read(updateEditionProvider)
            .offers(offer, currentVersion: running)) {
      return const UpdateStatusCurrent();
    }
    return UpdateStatusAvailable(offer);
  }

  /// Re-applies the edition filter to the result already held.
  ///
  /// Leaves an in-flight check alone — it reads the edition when it publishes
  /// — and leaves a failed one alone, because a licence change says nothing
  /// about whether the manifest could be fetched.
  void _republish() {
    if (state is UpdateStatusChecking || state is UpdateStatusError) return;
    state = _present();
  }
}

/// The app-wide update status, and the notifier that drives every check.
///
/// Keep-alive: the notifier owns the periodic timer, so it must outlive any
/// single widget. Reading it for the first time starts the launch check.
final NotifierProvider<UpdateStatusNotifier, UpdateStatus>
updateStatusProvider = NotifierProvider<UpdateStatusNotifier, UpdateStatus>(
  UpdateStatusNotifier.new,
  name: 'updateStatusProvider',
);
