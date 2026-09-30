// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite pure-Dart async/timing primitives for the EDACrux suite.
///
/// Exports `Debouncer`, the one trailing-edge debounce implementation every
/// product coalesces rapid input (keystrokes, slider drags, resize events)
/// through. See the package README for the cancel/flush/dispose contract.
library;

export 'src/debouncer.dart';
