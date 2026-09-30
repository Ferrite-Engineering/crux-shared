// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite shared action infrastructure for the EDACrux suite.
///
/// Exports the `ActionCategory` grouping enum and the `CruxAction` abstract
/// interface every product's action enum implements. See the package README
/// for the canonical usage pattern.
library;

export 'src/action_category.dart';
export 'src/crux_action.dart';
