// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/managed_install.dart';

/// Web (and any target without `dart:io`) can never be a managed install.
///
/// A browser build is not deployed by SCCM, apt or dnf — it is served, and the
/// server decides its version. Returning [ManagedInstall.unmanaged] here is not
/// a fallback but the correct answer.
///
/// [markerPath] is accepted and ignored so the two implementations share one
/// signature; see `managed_install_probe_io.dart` for the real one.
ManagedInstall probeManagedInstall({String? markerPath}) =>
    ManagedInstall.unmanaged;
