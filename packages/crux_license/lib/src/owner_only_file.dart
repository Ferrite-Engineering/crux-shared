// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Creating a file that only its owner can read, which `dart:io` cannot do,
/// dispatched by platform.
///
/// The licence fallback file needs it (`LicenseFallbackFile`). The
/// implementation calls the C library's `mkstemp` through `dart:ffi`; a
/// browser build has no `dart:ffi` and no files, and gets a stub that
/// creates nothing.
library;

export 'owner_only_file_stub.dart'
    if (dart.library.ffi) 'owner_only_file_ffi.dart';
