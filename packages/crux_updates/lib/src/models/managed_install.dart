// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How the running application was deployed.
///
/// An app installed from an MSI, a `.deb` or a `.rpm` is version-managed by the
/// organization's deployment tooling (SCCM, Intune, apt, dnf). It must not
/// offer an in-app update and must not nag: the administrator decides when the
/// fleet moves, and an app that updates itself out from under them breaks that
/// promise.
///
/// The signal is an **install-time marker file** laid down by the package —
/// `.managed-install`, beside the executable. Presence is the whole signal.
///
/// **This outranks every policy key**, including `suite.updateChannel`,
/// `suite.pinnedVersion` and `suite.manifestUrl`. It describes *how the app was
/// installed*, not what an administrator configured, and conflating the two
/// would let an admin who sets `updateChannel: stable` silently re-enable
/// self-update across an SCCM-managed fleet. `crux_policy` is deliberately not
/// consulted here, and this package deliberately does not depend on it.
@immutable
final class ManagedInstall {
  /// Creates a managed-install verdict.
  const ManagedInstall({required this.isManaged, this.mechanism});

  /// The verdict for an ordinary user-installed build: updates are ours to
  /// offer. Also the answer on web, and whenever detection cannot run.
  static const ManagedInstall unmanaged = ManagedInstall(isManaged: false);

  /// Whether a deployment system owns this installation's version.
  final bool isManaged;

  /// The deploying mechanism as named by the marker's body — `msi`, `deb`,
  /// `rpm` — or `null` when the marker was empty or unreadable.
  ///
  /// **Advisory only.** It exists for the About panel and support tickets. An
  /// unrecognised or absent body still means *managed*: the file's presence is
  /// the signal, and a package that writes a mechanism name we have not seen
  /// yet must not be treated as unmanaged just because we cannot label it.
  final String? mechanism;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedInstall &&
          runtimeType == other.runtimeType &&
          isManaged == other.isManaged &&
          mechanism == other.mechanism;

  @override
  int get hashCode => Object.hash(isManaged, mechanism);

  @override
  String toString() =>
      'ManagedInstall(isManaged: $isManaged, mechanism: $mechanism)';
}
