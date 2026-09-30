// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Setting a POSIX file mode, which `dart:io` cannot do, dispatched by
/// platform.
///
/// The manifest writer needs it to keep a peer's token private (CXP
/// §10.1–10.2). The implementation calls the C library's `chmod` through
/// `dart:ffi`; a browser build has no `dart:ffi` and no files, and gets a
/// stub that sets nothing.
library;

export 'cxp_file_mode_stub.dart' if (dart.library.ffi) 'cxp_file_mode_ffi.dart';
