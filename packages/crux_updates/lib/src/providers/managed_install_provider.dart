// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/managed_install.dart';
import 'package:crux_updates/src/services/managed_install_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overrides where the managed-install marker is looked for.
///
/// The injectable seam that makes this feature testable **without an installed
/// package**, which was a stated requirement of the decision: a test writes a
/// `.managed-install` into a temp directory, overrides this provider with that
/// path, and asserts the update check is suppressed.
///
/// `null` — the default — means "use the real location beside the running
/// executable".
final Provider<String?> managedInstallMarkerPathProvider = Provider<String?>(
  (_) => null,
  name: 'managedInstallMarkerPathProvider',
);

/// Whether this installation is version-managed by deployment tooling.
///
/// Synchronous and computed once per container. See [ManagedInstall] for why
/// this outranks every policy key, and `managed_install_probe_io.dart` for why
/// every failure resolves to *unmanaged* rather than *managed*.
final Provider<ManagedInstall> managedInstallProvider =
    Provider<ManagedInstall>(
      (ref) => probeManagedInstall(
        markerPath: ref.watch(managedInstallMarkerPathProvider),
      ),
      name: 'managedInstallProvider',
    );
