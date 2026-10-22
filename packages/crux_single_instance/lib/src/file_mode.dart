// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Setting a POSIX file mode, which `dart:io` cannot do, dispatched by
/// platform.
///
/// The rendezvous directory and the token file are kept private to the user
/// with it. The implementation calls the C library's `chmod` through
/// `dart:ffi`; a browser build has no `dart:ffi` and no files, and gets a stub
/// that sets nothing.
library;

export 'file_mode_stub.dart' if (dart.library.ffi) 'file_mode_ffi.dart';
