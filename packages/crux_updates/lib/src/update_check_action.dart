// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/update_status.dart';
import 'package:crux_updates/src/providers/update_seam_providers.dart';
import 'package:crux_updates/src/providers/update_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs a manual "Check for Updates" and surfaces the result.
///
/// Backs each product's `checkForUpdates` action (Help menu / overflow /
/// command palette) and the About-box "Check for Updates" button. Calls
/// [UpdateStatusNotifier.checkNow], which always runs regardless of the
/// "automatically check for updates" setting. The outcome is surfaced as:
///
/// - **in flight** → a transient "Checking for updates…" SnackBar, replaced by
///   the outcome below as soon as the check resolves.
/// - **available** → nothing here; the `UpdateBanner` renders the banner from
///   the same provider state.
/// - **current** → a brief confirmation SnackBar naming the running version.
/// - **error** → a non-fatal "couldn't check for updates" SnackBar.
///
/// Never throws — the check itself can only resolve to a typed state.
Future<void> runManualUpdateCheck(BuildContext context, WidgetRef ref) async {
  // Capture the messenger + strings before the await so we don't reach back
  // through `context` across the async gap.
  final messenger = ScaffoldMessenger.of(context);
  final strings = ref.read(cruxUpdateStringsProvider);

  messenger.showSnackBar(
    SnackBar(
      content: Text(strings.checkInProgress),
      duration: const Duration(minutes: 1),
    ),
  );

  await ref.read(updateStatusProvider.notifier).checkNow();
  if (!context.mounted) return;
  // Retire the in-flight toast before reporting the outcome, so the two never
  // queue behind one another.
  messenger.hideCurrentSnackBar();

  switch (ref.read(updateStatusProvider)) {
    case UpdateStatusAvailable():
    case UpdateStatusChecking():
      // Available → the UpdateBanner surfaces it. Checking → transient.
      break;
    case UpdateStatusError():
      messenger.showSnackBar(SnackBar(content: Text(strings.checkFailed)));
    case UpdateStatusCurrent():
      final version = ref.read(updateBuildInfoProvider).value?.version ?? '';
      messenger.showSnackBar(
        SnackBar(content: Text(strings.checkUpToDate(version))),
      );
  }
}
