// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// About-box extension-point models for the EDACrux suite.
///
/// Every product in the suite ships an About dialog that displays the
/// application edition, build metadata, and company branding. The Riverpod
/// providers and Flutter widgets that render this dialog live in each
/// product; this package owns the *data shapes* those providers return so all
/// products carry consistent fields.
library;

export 'src/application_branding.dart';
export 'src/application_build_info.dart';
