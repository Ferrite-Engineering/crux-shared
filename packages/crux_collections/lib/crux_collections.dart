// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite pure-Dart collection primitives for the EDACrux suite.
///
/// Exports `LruCache`, the one bounded least-recently-used cache every
/// product's memo, label-layout and log-buffer cache evicts through. It was
/// written four times across the suite before it was written once here, and
/// the copies differed in exactly the places a cache goes wrong: whether a
/// cached `null` counts as a hit, whether the bound is entries or the weight
/// that tracks memory, whether an evicted value is disposed, and whether a
/// value still in use can be evicted at all. See the package README.
library;

export 'src/lru_cache.dart';
