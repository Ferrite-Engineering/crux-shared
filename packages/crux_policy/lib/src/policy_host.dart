// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// What the loader needs from its host — the process environment, the
/// operating system's name, and a file read — dispatched by platform.
///
/// The products ship web builds that read the policy file on the same startup
/// path as desktop. A bare `Platform.environment` there throws
/// `UnsupportedError` before the first frame. The conditional export keeps
/// `dart:io` out of the web build entirely, and the stub answers the way a
/// machine with no policy file does: nothing to read.
library;

export 'policy_host_stub.dart' if (dart.library.io) 'policy_host_io.dart';
