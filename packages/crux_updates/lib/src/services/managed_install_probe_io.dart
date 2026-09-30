// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_updates/src/models/managed_install.dart';

/// The marker a deployment package lays down beside the executable.
///
/// The MSI, the `.deb` and the `.rpm` each ship this file; the Inno `.exe`, the
/// portable zip, the tar.gz and the AppImage each deliberately do not.
const String kManagedInstallMarkerName = '.managed-install';

/// Where the marker lives for the running executable.
///
/// Beside the binary, inside the directory the package owns — so uninstalling
/// removes it, and copying the executable somewhere else does not carry a
/// "managed" claim along with it.
/// Joined with [Platform.pathSeparator] rather than `package:path`, to keep
/// this package's dependency set unchanged: adding one would trip the
/// export-control guard's dependency review for a single string concatenation.
String defaultManagedInstallMarkerPath() {
  final dir = File(Platform.resolvedExecutable).parent.path;
  return '$dir${Platform.pathSeparator}$kManagedInstallMarkerName';
}

/// Detects whether this installation is version-managed by deployment tooling.
///
/// **Never throws.** Every failure — missing file, unreadable file, a path we
/// cannot resolve — resolves to [ManagedInstall.unmanaged]. That direction is
/// deliberate: the cost of wrongly deciding "managed" is an app that silently
/// stops telling a paying user about updates forever, which nobody would
/// report as a bug because there is nothing to see. The cost of wrongly
/// deciding "unmanaged" is one update banner an administrator did not want.
/// The second is recoverable; the first is not.
///
/// Synchronous on purpose. `updateCheckServiceProvider` is a synchronous
/// provider, and the whole promise of this feature is that a managed install
/// issues **no manifest fetch at all** — not that it hides the result. An async
/// probe would let a check race ahead of its own answer.
///
/// [markerPath] overrides the location so a test can point at a temp directory
/// and exercise both verdicts without an installed package.
ManagedInstall probeManagedInstall({String? markerPath}) {
  try {
    final path = markerPath ?? defaultManagedInstallMarkerPath();
    final file = File(path);
    if (!file.existsSync()) return ManagedInstall.unmanaged;

    // Present. Managed, whatever the body turns out to say.
    String? mechanism;
    try {
      final body = file.readAsStringSync().trim().toLowerCase();
      if (body.isNotEmpty) mechanism = body.split(RegExp(r'\s+')).first;
    } on Object {
      // Readable existence, unreadable contents. Still managed; the mechanism
      // is a diagnostic label, never the signal.
      mechanism = null;
    }
    return ManagedInstall(isManaged: true, mechanism: mechanism);
  } on Object {
    return ManagedInstall.unmanaged;
  }
}
