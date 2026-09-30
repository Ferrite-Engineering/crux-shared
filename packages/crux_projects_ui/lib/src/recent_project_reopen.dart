// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tells the user that [recent] could not be reopened, because the registry
/// refused its path with [error].
///
/// By the time the entry is dropped from the recents list, the row that asked
/// is gone with it, so this is called first, with a [context] that is still
/// mounted.
typedef CruxRecentProjectUnavailableReporter =
    void Function(
      BuildContext context,
      ProjectDescriptor recent,
      ProjectLoadException error,
    );

/// The host's [CruxRecentProjectUnavailableReporter], or `null`.
///
/// The words are the host's, like every other string this package shows,
/// so the host also chooses how to show them (usually an error snack naming
/// the project and the path it looked at). Unbound, a refused reopen still
/// drops the entry, and the row leaving the list is visible, but nothing
/// says why. A host should bind it.
final Provider<CruxRecentProjectUnavailableReporter?>
recentProjectUnavailableReporterProvider =
    Provider<CruxRecentProjectUnavailableReporter?>(
      (ref) => null,
      name: 'recentProjectUnavailableReporterProvider',
    );

/// Reopens [recent] through [registry], and returns whether it opened.
///
/// A registry refuses a path it cannot load with a [ProjectLoadException];
/// for a persistent registry that means the project's folder was moved or
/// deleted after it was closed. That entry can never open, and left in the
/// list every press would fail on it the same way, so it is dropped. [report]
/// is called before the drop, while [context] is still mounted.
///
/// Takes the registry and the reporter rather than a `WidgetRef`: the caller
/// reads them before the await, because a project that does reopen leaves
/// the recents list, and the row that pressed Reopen leaves the tree.
Future<bool> reopenRecentProject({
  required ProjectRegistry registry,
  required ProjectDescriptor recent,
  required BuildContext context,
  CruxRecentProjectUnavailableReporter? report,
}) async {
  try {
    await registry.openProject(recent.projectPath);
    return true;
  } on ProjectLoadException catch (error) {
    if (context.mounted) report?.call(context, recent, error);
    await registry.clearRecentProject(recent.id);
    return false;
  }
}
