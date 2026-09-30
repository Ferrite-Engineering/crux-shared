// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The host half of path identity — the platform's case rule and the
/// filesystem canonicalization — dispatched by platform.
///
/// The products' web builds key tabs and recent items by location through the
/// same functions desktop builds use. In a browser `Platform.isMacOS` throws
/// `UnsupportedError`, and `package:path` resolves a relative name against the
/// page URL, so the web answer has to come from a stub rather than from
/// `dart:io`.
library;

export 'path_identity_host_stub.dart'
    if (dart.library.io) 'path_identity_host_io.dart';
