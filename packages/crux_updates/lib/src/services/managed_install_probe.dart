// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Platform-dispatched managed-install detection.
///
/// `crux_updates` carried no `dart:io` import before this feature and must not
/// start: the products ship web builds, and a bare `File()` here would break
/// them at compile time. The conditional export keeps the detection logic in
/// one place — rather than duplicating it into four products — while leaving
/// the package web-safe.
library;

export 'managed_install_probe_stub.dart'
    if (dart.library.io) 'managed_install_probe_io.dart';
