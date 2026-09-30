// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/element_id.dart';
import 'package:meta/meta.dart';

/// Maps product-local element references into and out of canonical
/// [ElementId] form.
///
/// Each Crux product implements its own resolver as part of its CXP
/// integration phase. WaveCrux maps hierarchical signal paths
/// (`top.cpu.alu.sum[31:0]`) to [ElementKind.signal] [ElementId]s; future
/// Crux products map their own domains (elaborated names, rule sites,
/// breakpoints and tests. The resolver is the seam at which products
/// agree on a common name space.
///
/// Implementations must be stateless and thread-safe — the same resolver
/// instance is used concurrently from inbound and outbound message paths.
abstract class NameResolver {
  /// Convert a product-local reference [local] of the given [kind] into
  /// canonical form.
  ///
  /// Returns `null` if the resolver cannot map the local reference (e.g.
  /// the kind is not handled, or the local form is malformed). Callers
  /// must handle `null` by skipping the outbound message.
  ElementId? toCanonical({required ElementKind kind, required String local});

  /// Convert a canonical [id] into a product-local reference.
  ///
  /// Returns `null` if the resolver cannot map the canonical form back to
  /// a local object (e.g. the referenced element does not exist in this
  /// product's current state). Callers must handle `null` by sending an
  /// `ErrorResponse` when a request cannot be honoured.
  String? toLocal(ElementId id);
}

/// Resolver that maps every kind/path combination to `null`.
///
/// Used in tests and in default no-op CXP server registrations so the
/// CXP infrastructure starts up cleanly before a product has wired in
/// its concrete resolver.
@immutable
class NoopNameResolver implements NameResolver {
  /// Const constructor — there is no state.
  const NoopNameResolver();

  @override
  ElementId? toCanonical({required ElementKind kind, required String local}) =>
      null;

  @override
  String? toLocal(ElementId id) => null;
}

/// Resolver that treats every local reference as already canonical.
///
/// Useful for proof-of-concept integrations where the product has not yet
/// implemented its own name canonicalisation, and for tests that exercise
/// the protocol without exercising the name-mapping layer.
@immutable
class IdentityNameResolver implements NameResolver {
  /// Const constructor — there is no state.
  const IdentityNameResolver();

  @override
  ElementId? toCanonical({required ElementKind kind, required String local}) =>
      ElementId(kind: kind, path: local);

  @override
  String? toLocal(ElementId id) => id.path;
}
