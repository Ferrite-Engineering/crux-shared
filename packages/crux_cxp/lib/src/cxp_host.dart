// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// What resolving the shared CXP directories needs from the host — the
/// process environment and the operating system's name — dispatched by
/// platform.
///
/// The products ship web builds, and each resolves the shared manifest
/// directory on the path that starts its CXP server. A bare
/// `Platform.environment` there throws `UnsupportedError` from inside
/// `dart:io`. The conditional export keeps `dart:io` out of this lookup on the
/// web, and the stub answers "no host to ask", which the resolver turns into
/// its documented `StateError`.
library;

export 'cxp_host_stub.dart' if (dart.library.io) 'cxp_host_io.dart';
