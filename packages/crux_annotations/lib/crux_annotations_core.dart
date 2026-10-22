// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The `dart:ui`-free subset of `crux_annotations`: the anchor and witness
/// contracts, the label placement and its record codec, and the status
/// vocabulary with its decision table.
///
/// For a product's domain models and anything a headless build compiles,
/// which must not reach `dart:ui`. The main barrel re-exports all of it.
library;

export 'src/anchor.dart';
export 'src/placement.dart';
export 'src/status.dart';
